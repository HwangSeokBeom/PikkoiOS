import Foundation

struct RequestBuilder: Sendable {
    private let configuration: AppConfiguration
    private let tokenStore: any TokenStore

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
        let baseURL: URL

        if let absoluteURL = URL(string: path), absoluteURL.scheme != nil {
            baseURL = absoluteURL
        } else if let relativeURL = URL(string: path, relativeTo: configuration.baseURL)?.absoluteURL {
            baseURL = relativeURL
        } else {
            throw NetworkError.invalidRequest
        }

        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw NetworkError.invalidRequest
        }

        if !query.isEmpty {
            components.queryItems = query
        }

        guard let url = components.url else {
            throw NetworkError.invalidRequest
        }

        return url
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
            request.setValue(tokens.refreshToken, forHTTPHeaderField: "RefreshToken")
        }
    }
}
