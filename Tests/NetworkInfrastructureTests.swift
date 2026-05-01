import XCTest
@testable import Pikko

final class NetworkInfrastructureTests: XCTestCase {
    override func tearDown() {
        URLProtocolStub.requestHandler = nil
        super.tearDown()
    }

    func testRequestBuilderInjectsSesacKeyAndRawAuthorizationHeader() async throws {
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

        XCTAssertEqual(request.value(forHTTPHeaderField: "SesacKey"), "test-sesac-key")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "access-token")
        XCTAssertNil(request.value(forHTTPHeaderField: "RefreshToken"))
    }

    func testRequestBuilderSkipsAuthorizationHeaderForPublicEndpoint() async throws {
        let tokenStore = StubTokenStore(tokens: nil)
        let configuration = AppConfiguration(
            environment: .development,
            baseURL: URL(string: "https://example.com")!,
            seSACKey: "test-sesac-key"
        )
        let requestBuilder = RequestBuilder(configuration: configuration, tokenStore: tokenStore)

        let endpoint = Endpoint<EmptyResponse>(
            path: "/v1/posts/search",
            method: .get,
            authorizationPolicy: .none
        )

        let request = try await requestBuilder.build(for: endpoint)

        XCTAssertEqual(request.value(forHTTPHeaderField: "SesacKey"), "test-sesac-key")
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
        XCTAssertNil(request.value(forHTTPHeaderField: "RefreshToken"))
    }

    func testSensitiveLogRedactorKeepsDiagnosticHeaderBooleansReadable() {
        let message = "[HLSProbeRequest] authMode=tokenOnly headerAuthorization=false headerSeSACKey=false headerContentType=false hasAuthorization=true hasSesacKey=true"

        XCTAssertEqual(SensitiveLogRedactor.redact(message), message)
    }

    func testSensitiveLogRedactorStillRedactsActualSensitiveFields() {
        let message = "Authorization=access-token token=playback-token SesacKey=api-key"
        let redacted = SensitiveLogRedactor.redact(message)

        XCTAssertEqual(redacted, "Authorization=<redacted> token=<redacted> SesacKey=<redacted>")
    }

    func testKakaoLoginUsesSwaggerPathOAuthTokenBodyAndNoAppAuthorization() async throws {
        let apiClient = RecordingAPIClient(
            response: LoginResponseDTO(
                userID: "server-user",
                email: "user@example.com",
                nick: "픽코",
                profileImage: nil,
                accessToken: "server-access",
                refreshToken: "server-refresh"
            )
        )
        let dataSource = AuthRemoteDataSource(apiClient: apiClient)

        _ = try await dataSource.signIn(
            with: SocialLoginCredential(
                provider: .kakao,
                accessToken: "kakao-oauth-token",
                idToken: "kakao-id-token",
                authorizationCode: nil,
                email: nil,
                nickname: nil,
                rawNonce: nil,
                userIdentifier: nil
            ),
            deviceToken: "device-token"
        )

        XCTAssertEqual(apiClient.recordedPath, "/v1/users/login/kakao")
        XCTAssertEqual(apiClient.recordedMethod, .post)
        XCTAssertEqual(apiClient.recordedAuthorizationPolicy, Optional.some(.none))

        guard case let .json(payload)? = apiClient.recordedBody else {
            return XCTFail("Expected Kakao login JSON body")
        }

        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: payload) as? [String: String])
        XCTAssertEqual(object["oauthToken"], "kakao-oauth-token")
        XCTAssertEqual(object["deviceToken"], "device-token")
        XCTAssertNil(object["idToken"])
        XCTAssertNil(object["provider"])
    }

    func testKakaoLoginRejectsMissingDeviceTokenBeforeSendingEmptyString() async throws {
        let apiClient = RecordingAPIClient(
            response: LoginResponseDTO(
                userID: "server-user",
                email: "user@example.com",
                nick: "픽코",
                profileImage: nil,
                accessToken: "server-access",
                refreshToken: "server-refresh"
            )
        )
        let dataSource = AuthRemoteDataSource(apiClient: apiClient)

        do {
            _ = try await dataSource.signIn(
                with: SocialLoginCredential(
                    provider: .kakao,
                    accessToken: "kakao-oauth-token",
                    idToken: "kakao-id-token",
                    authorizationCode: nil,
                    email: nil,
                    nickname: nil,
                    rawNonce: nil,
                    userIdentifier: nil
                ),
                deviceToken: nil
            )
            XCTFail("Expected missing device token to fail before sending")
        } catch let error as NetworkError {
            XCTAssertEqual(error, .invalidRequest)
        }

        XCTAssertNil(apiClient.recordedPath)
        XCTAssertNil(apiClient.recordedBody)
    }

    func testLoginResponseDecodesSwaggerMixedCaseKeys() throws {
        let data = """
        {
          "user_id": "server-user",
          "email": "user@example.com",
          "nick": "새싹이Abc12",
          "profileImage": "/data/profiles/user.png",
          "accessToken": "server-access",
          "refreshToken": "server-refresh"
        }
        """.data(using: .utf8)!

        let response = try NetworkCoding.makeJSONDecoder().decode(LoginResponseDTO.self, from: data)

        XCTAssertEqual(response.userID, "server-user")
        XCTAssertEqual(response.email, "user@example.com")
        XCTAssertEqual(response.nick, "새싹이Abc12")
        XCTAssertEqual(response.profileImage, "/data/profiles/user.png")
        XCTAssertEqual(response.accessToken, "server-access")
        XCTAssertEqual(response.refreshToken, "server-refresh")
    }

    func testRequestBuilderBuildsPickupURLWithoutCollapsingHostToV1() async throws {
        let tokenStore = StubTokenStore(tokens: nil)
        let configuration = AppConfiguration(
            environment: .development,
            baseURL: URL(string: "http://pickup.sesac.kr:42678/")!,
            seSACKey: "test-sesac-key"
        )
        let requestBuilder = RequestBuilder(configuration: configuration, tokenStore: tokenStore)

        let endpoint = Endpoint<EmptyResponse>(
            path: "/v1/stores/searches-popular",
            method: .get,
            authorizationPolicy: .none
        )

        let request = try await requestBuilder.build(for: endpoint)

        XCTAssertEqual(
            request.url?.absoluteString,
            "http://pickup.sesac.kr:42678/v1/stores/searches-popular"
        )
    }

    func testRequestBuilderNormalizesTrailingAndLeadingSlashes() async throws {
        let tokenStore = StubTokenStore(tokens: nil)
        let configuration = AppConfiguration(
            environment: .development,
            baseURL: URL(string: "http://pickup.sesac.kr:42678")!,
            seSACKey: "test-sesac-key"
        )
        let requestBuilder = RequestBuilder(configuration: configuration, tokenStore: tokenStore)

        let endpoint = Endpoint<EmptyResponse>(
            path: "v1/banners/main",
            method: .get,
            authorizationPolicy: .none
        )

        let request = try await requestBuilder.build(for: endpoint)

        XCTAssertEqual(
            request.url?.absoluteString,
            "http://pickup.sesac.kr:42678/v1/banners/main"
        )
    }

    func testRequestBuilderPercentEncodesKoreanQueryItems() async throws {
        let tokenStore = StubTokenStore(tokens: nil)
        let configuration = AppConfiguration(
            environment: .development,
            baseURL: URL(string: "http://pickup.sesac.kr:42678/")!,
            seSACKey: "test-sesac-key"
        )
        let requestBuilder = RequestBuilder(configuration: configuration, tokenStore: tokenStore)

        let endpoint = Endpoint<EmptyResponse>(
            path: "/v1/stores/popular-stores",
            method: .get,
            query: [URLQueryItem(name: "category", value: "커피")],
            authorizationPolicy: .none
        )

        let request = try await requestBuilder.build(for: endpoint)

        XCTAssertEqual(
            request.url?.absoluteString,
            "http://pickup.sesac.kr:42678/v1/stores/popular-stores?category=%EC%BB%A4%ED%94%BC"
        )
    }

    func testCommunityRemoteDataSourceBuildsMultipartFilesFieldForPostUploads() async throws {
        let apiClient = RecordingAPIClient(
            fileUploadResponse: CommunityFileUploadResponseDTO(files: ["/data/posts/uploaded.jpg"])
        )
        let dataSource = CommunityRemoteDataSource(apiClient: apiClient)

        _ = try await dataSource.uploadPostFiles([
            CommunityPostUploadFile(
                data: Data("image-bytes".utf8),
                fileName: "sample.jpg",
                mimeType: "image/jpeg"
            )
        ])

        XCTAssertEqual(apiClient.recordedPath, "/v1/posts/files")
        XCTAssertEqual(apiClient.recordedMethod, .post)

        guard case let .multipart(payload, boundary)? = apiClient.recordedBody else {
            return XCTFail("Expected multipart request body")
        }

        let payloadString = String(decoding: payload, as: UTF8.self)
        XCTAssertTrue(payloadString.contains("name=\"files\"; filename=\"sample.jpg\""))
        XCTAssertTrue(payloadString.contains("Content-Type: image/jpeg"))
        XCTAssertTrue(boundary.isEmpty == false)
    }

    func testReviewRemoteDataSourceBuildsMultipartFilesFieldForReviewUploads() async throws {
        let apiClient = RecordingAPIClient(
            response: ReviewImageResponseDTO(reviewImageURLs: ["/data/reviews/uploaded.jpg"])
        )
        let dataSource = ReviewRemoteDataSource(apiClient: apiClient)

        _ = try await dataSource.uploadReviewImages(
            storeID: "store-1",
            files: [
                StoreReviewUploadFile(
                    data: Data("review-image-bytes".utf8),
                    fileName: "review.jpg",
                    mimeType: "image/jpeg"
                )
            ]
        )

        XCTAssertEqual(apiClient.recordedPath, "/v1/stores/store-1/reviews/files")
        XCTAssertEqual(apiClient.recordedMethod, .post)

        guard case let .multipart(payload, boundary)? = apiClient.recordedBody else {
            return XCTFail("Expected multipart request body")
        }

        let payloadString = String(decoding: payload, as: UTF8.self)
        XCTAssertTrue(payloadString.contains("name=\"files\"; filename=\"review.jpg\""))
        XCTAssertTrue(payloadString.contains("Content-Type: image/jpeg"))
        XCTAssertTrue(boundary.isEmpty == false)
    }

    func testRequestBuilderRejectsRelativeV1BaseURL() async {
        await assertRequestBuilderRejectsInvalidBaseURL(URL(string: "v1")!)
    }

    func testRequestBuilderRejectsPathOnlyV1BaseURL() async {
        await assertRequestBuilderRejectsInvalidBaseURL(URL(string: "/v1")!)
    }

    func testRequestBuilderRejectsV1HostBaseURL() async {
        await assertRequestBuilderRejectsInvalidBaseURL(URL(string: "http://v1")!)
    }

    func testRequestBuilderRejectsPlaceholderSeSACKeyBeforeSendingRequest() async {
        let tokenStore = StubTokenStore(tokens: nil)
        let configuration = AppConfiguration(
            environment: .development,
            baseURL: URL(string: "https://example.com")!,
            seSACKey: "REPLACE_WITH_SESAC_KEY"
        )
        let requestBuilder = RequestBuilder(configuration: configuration, tokenStore: tokenStore)

        let endpoint = Endpoint<EmptyResponse>(
            path: "/v1/stores",
            method: .get,
            authorizationPolicy: .none
        )

        do {
            _ = try await requestBuilder.build(for: endpoint)
            XCTFail("Expected configuration error")
        } catch let error as NetworkError {
            XCTAssertEqual(error, .configuration(.invalidSeSACKey))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testHTTPStatusMapperPreservesBadRequestServerMessage() {
        let data = #"{"message":"유효하지 않은 결제건입니다."}"#.data(using: .utf8)!

        let error = HTTPStatusMapper.map(statusCode: 400, data: data)

        XCTAssertEqual(error, .abnormalRequest(message: "유효하지 않은 결제건입니다."))
    }

    func testHTTPStatusMapperPreservesUnauthorizedServerMessage() {
        let data = #"{"message":"계정을 확인해주세요."}"#.data(using: .utf8)!

        let error = HTTPStatusMapper.map(statusCode: 401, data: data)

        XCTAssertEqual(error, .authenticationFailed(message: "계정을 확인해주세요."))
    }

    func testHTTPStatusMapperPreservesConflictServerMessage() {
        let data = #"{"message":"이미 가입된 유저입니다."}"#.data(using: .utf8)!

        let error = HTTPStatusMapper.map(statusCode: 409, data: data)

        XCTAssertEqual(error, .conflict(message: "이미 가입된 유저입니다."))
    }

    func testAPIClientRefreshesOn401AndRetriesOriginalRequestOnce() async throws {
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
            switch request.url?.path {
            case "/v1/orders":
                counter.storeRequestCount += 1

                if counter.storeRequestCount == 1 {
                    XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "expired-access")
                    return (
                        HTTPURLResponse(
                            url: request.url!,
                            statusCode: 401,
                            httpVersion: nil,
                            headerFields: nil
                        )!,
                        #"{"message":"unauthorized"}"#.data(using: .utf8)!
                    )
                }

                XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "new-access")
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
                XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "expired-access")
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
                XCTFail("Unexpected request path: \(request.url?.path ?? "nil")")
                throw URLError(.badURL)
            }
        }

        let endpoint = Endpoint<TestResponseDTO>(
            path: "/v1/orders",
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
                XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "expired-access")
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

    func testAPIClientInvalidatesSessionWhenProtectedRequestHasNoToken() async throws {
        let tokenStore = StubTokenStore(tokens: nil)
        let configuration = AppConfiguration(
            environment: .development,
            baseURL: URL(string: "https://example.com")!,
            seSACKey: "test-sesac-key"
        )
        let requestBuilder = RequestBuilder(configuration: configuration, tokenStore: tokenStore)
        let session = URLSession(configuration: .ephemeral)
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

        let invalidationExpectation = expectation(
            forNotification: .pikkoSessionDidInvalidate,
            object: nil
        )

        let endpoint = Endpoint<TestResponseDTO>(
            path: "/v1/stores",
            method: .get,
            authorizationPolicy: .accessToken
        )

        do {
            _ = try await apiClient.execute(endpoint)
            XCTFail("Expected unauthorized error")
        } catch let error as NetworkError {
            XCTAssertEqual(error, .unauthorized)
        }

        await fulfillment(of: [invalidationExpectation], timeout: 1.0)
        let storedTokens = try await tokenStore.loadTokens()
        XCTAssertNil(storedTokens)
    }

    func testAPIClientDoesNotInvalidateSessionForVideoStreamForbidden() async throws {
        let tokenStore = StubTokenStore(
            tokens: StoredTokens(accessToken: "access-token", refreshToken: "refresh-token")
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

        let invalidationExpectation = expectation(
            forNotification: .pikkoSessionDidInvalidate,
            object: nil
        )
        invalidationExpectation.isInverted = true

        URLProtocolStub.requestHandler = { request in
            XCTAssertEqual(request.url?.path, "/v1/videos/video-1/stream")
            return (
                HTTPURLResponse(
                    url: request.url!,
                    statusCode: 403,
                    httpVersion: nil,
                    headerFields: nil
                )!,
                #"{"message":"Forbidden"}"#.data(using: .utf8)!
            )
        }

        let endpoint = Endpoint<TestResponseDTO>(
            path: "/v1/videos/video-1/stream",
            method: .get,
            authorizationPolicy: .accessToken
        )

        do {
            _ = try await apiClient.execute(endpoint)
            XCTFail("Expected forbidden error")
        } catch let error as NetworkError {
            XCTAssertEqual(error, .forbidden)
        }

        await fulfillment(of: [invalidationExpectation], timeout: 0.2)
        let storedTokens = try await tokenStore.loadTokens()
        XCTAssertEqual(storedTokens, StoredTokens(accessToken: "access-token", refreshToken: "refresh-token"))
    }
}

extension NetworkInfrastructureTests {
    private func assertRequestBuilderRejectsInvalidBaseURL(_ baseURL: URL) async {
        let tokenStore = StubTokenStore(tokens: nil)
        let configuration = AppConfiguration(
            environment: .development,
            baseURL: baseURL,
            seSACKey: "test-sesac-key"
        )
        let requestBuilder = RequestBuilder(configuration: configuration, tokenStore: tokenStore)
        let endpoint = Endpoint<EmptyResponse>(
            path: "/v1/stores",
            method: .get,
            authorizationPolicy: .none
        )

        do {
            _ = try await requestBuilder.build(for: endpoint)
            XCTFail("Expected invalid base URL configuration error")
        } catch let error as NetworkError {
            XCTAssertEqual(error, .configuration(.invalidBaseURL))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
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

private final class RecordingAPIClient: APIClientProtocol, @unchecked Sendable {
    let response: Any
    private(set) var recordedPath: String?
    private(set) var recordedMethod: HTTPMethod?
    private(set) var recordedBody: RequestBody?
    private(set) var recordedAuthorizationPolicy: AuthorizationPolicy?

    init(fileUploadResponse: CommunityFileUploadResponseDTO) {
        self.response = fileUploadResponse
    }

    init(response: Any) {
        self.response = response
    }

    func execute<ResponseDTO>(_ endpoint: Endpoint<ResponseDTO>) async throws -> ResponseDTO where ResponseDTO : Decodable, ResponseDTO : Sendable {
        recordedPath = endpoint.path
        recordedMethod = endpoint.method
        recordedBody = endpoint.body
        recordedAuthorizationPolicy = endpoint.authorizationPolicy

        if let response = response as? ResponseDTO {
            return response
        }

        throw NetworkError.decoding
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
