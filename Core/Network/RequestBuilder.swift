import Foundation

struct RequestBuilder: Sendable {
    private let configuration: AppConfiguration
    private let tokenStore: any TokenStore
    private let urlBuilder = URLBuilder()

    init(configuration: AppConfiguration, tokenStore: any TokenStore) {
        self.configuration = configuration
        self.tokenStore = tokenStore
    }

    func build<ResponseDTO: Decodable & Sendable>(
        for endpoint: Endpoint<ResponseDTO>
    ) async throws -> URLRequest {
        let url = try makeURL(path: endpoint.path, query: endpoint.query)
        var request = URLRequest(url: url)
        request.httpMethod = endpoint.method.rawValue
        request.timeoutInterval = endpoint.timeout.resolve(with: configuration)
        guard configuration.hasValidSeSACKey else {
            throw NetworkError.configuration(configuration.seSACKeyError ?? .missingSeSACKey)
        }
        request.setValue(configuration.seSACKey, forHTTPHeaderField: "SeSACKey")

        try await applyAuthorizationHeaders(to: &request, policy: endpoint.authorizationPolicy)

        for (field, value) in endpoint.headers {
            request.setValue(value, forHTTPHeaderField: field)
        }

        if let body = endpoint.body {
            request.httpBody = body.payload
            if request.value(forHTTPHeaderField: "Content-Type") == nil {
                request.setValue(body.contentType, forHTTPHeaderField: "Content-Type")
            }
        }

        return request
    }

    private func makeURL(path: String, query: [URLQueryItem]) throws -> URL {
        guard let baseURL = configuration.baseURL else {
            throw NetworkError.configuration(configuration.baseURLError ?? .missingBaseURL)
        }

        return try urlBuilder.makeURL(
            baseURL: baseURL,
            path: path,
            query: query
        )
    }

    private func applyAuthorizationHeaders(
        to request: inout URLRequest,
        policy: AuthorizationPolicy
    ) async throws {
        switch policy {
        case .none:
            return
        case .accessToken, .fileAuthorized:
            guard let tokens = try await tokenStore.loadTokens() else {
                throw NetworkError.unauthorized
            }
            request.setValue(
                configuration.authorizationHeaderFormat.format(tokens.accessToken),
                forHTTPHeaderField: "Authorization"
            )
        case .refreshToken:
            guard let tokens = try await tokenStore.loadTokens() else {
                throw NetworkError.refreshTokenExpired
            }
            request.setValue(
                configuration.authorizationHeaderFormat.format(tokens.accessToken),
                forHTTPHeaderField: "Authorization"
            )
            request.setValue(tokens.refreshToken, forHTTPHeaderField: "RefreshToken")
        }
    }
}
