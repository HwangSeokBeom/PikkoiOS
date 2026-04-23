import XCTest
@testable import Pikko

final class NetworkInfrastructureTests: XCTestCase {
    override func tearDown() {
        URLProtocolStub.requestHandler = nil
        super.tearDown()
    }

    func testRequestBuilderInjectsSeSACKeyAndRawAuthorizationHeader() async throws {
        let tokenStore = StubTokenStore(
            tokens: StoredTokens(accessToken: "access-token", refreshToken: "refresh-token")
        )
        let configuration = AppConfiguration(
            environment: .development,
            baseURL: URL(string: "https://example.com")!,
            seSACKey: "test-sesac-key"
        )
        let requestBuilder = RequestBuilder(configuration: configuration, tokenStore: tokenStore)

        let endpoint = Endpoint<EmptyResponse>(
            path: "/v1/stores",
            method: .get,
            authorizationPolicy: .accessToken
        )

        let request = try await requestBuilder.build(for: endpoint)

        XCTAssertEqual(request.value(forHTTPHeaderField: "SeSACKey"), "test-sesac-key")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "access-token")
        XCTAssertNil(request.value(forHTTPHeaderField: "RefreshToken"))
    }

    func testAPIClientRefreshesOn419AndRetriesOriginalRequestOnce() async throws {
        let tokenStore = StubTokenStore(
            tokens: StoredTokens(accessToken: "expired-access", refreshToken: "refresh-token")
        )
        let configuration = AppConfiguration(
            environment: .development,
            baseURL: URL(string: "https://example.com")!,
            seSACKey: "test-sesac-key"
        )
        let requestBuilder = RequestBuilder(configuration: configuration, tokenStore: tokenStore)

        let sessionConfiguration = URLSessionConfiguration.ephemeral
        sessionConfiguration.protocolClasses = [URLProtocolStub.self]
        let session = URLSession(configuration: sessionConfiguration)

        let refreshCoordinator = TokenRefreshCoordinator(
            session: session,
            requestBuilder: requestBuilder,
            tokenStore: tokenStore
        )
        let apiClient = APIClient(
            session: session,
            requestBuilder: requestBuilder,
            tokenRefreshCoordinator: refreshCoordinator
        )

        final class RequestCounter {
            var storeRequestCount = 0
            var refreshRequestCount = 0
        }

        let counter = RequestCounter()

        URLProtocolStub.requestHandler = { request in
            let path = request.url?.path

            switch path {
            case "/v1/stores":
                counter.storeRequestCount += 1

                let authorizationHeader = request.value(forHTTPHeaderField: "Authorization")
                if counter.storeRequestCount == 1 {
                    XCTAssertEqual(authorizationHeader, "expired-access")
                    return (
                        HTTPURLResponse(
                            url: request.url!,
                            statusCode: 419,
                            httpVersion: nil,
                            headerFields: nil
                        )!,
                        #"{"message":"access token expired"}"#.data(using: .utf8)!
                    )
                }

                XCTAssertEqual(authorizationHeader, "new-access")
                return (
                    HTTPURLResponse(
                        url: request.url!,
                        statusCode: 200,
                        httpVersion: nil,
                        headerFields: nil
                    )!,
                    #"{"value":"ok"}"#.data(using: .utf8)!
                )
            case "/v1/auth/refresh":
                counter.refreshRequestCount += 1
                XCTAssertEqual(request.value(forHTTPHeaderField: "RefreshToken"), "refresh-token")
                return (
                    HTTPURLResponse(
                        url: request.url!,
                        statusCode: 200,
                        httpVersion: nil,
                        headerFields: nil
                    )!,
                    #"{"accessToken":"new-access","refreshToken":"new-refresh"}"#.data(using: .utf8)!
                )
            default:
                XCTFail("Unexpected request path: \(path ?? "nil")")
                throw URLError(.badURL)
            }
        }

        let endpoint = Endpoint<TestResponseDTO>(
            path: "/v1/stores",
            method: .get,
            authorizationPolicy: .accessToken
        )

        let response = try await apiClient.execute(endpoint)
        let storedTokens = try await tokenStore.loadTokens()

        XCTAssertEqual(response.value, "ok")
        XCTAssertEqual(counter.storeRequestCount, 2)
        XCTAssertEqual(counter.refreshRequestCount, 1)
        XCTAssertEqual(storedTokens, StoredTokens(accessToken: "new-access", refreshToken: "new-refresh"))
    }
}

private struct TestResponseDTO: Decodable, Equatable, Sendable {
    let value: String
}

private actor StubTokenStore: TokenStore {
    private var storedTokens: StoredTokens?

    init(tokens: StoredTokens?) {
        self.storedTokens = tokens
    }

    func loadTokens() async throws -> StoredTokens? {
        storedTokens
    }

    func saveTokens(_ tokens: StoredTokens) async throws {
        storedTokens = tokens
    }

    func clearTokens() async throws {
        storedTokens = nil
    }
}

private final class URLProtocolStub: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.requestHandler else {
            fatalError("URLProtocolStub.requestHandler must be set before requests start.")
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
