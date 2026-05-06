import Foundation

enum HTTPHeaderField {
    static let authorization = "Authorization"
    static let contentType = "Content-Type"
    static let range = "Range"
    static let refreshToken = "RefreshToken"
    static let sesacKey = "SesacKey"
}

struct ProtectedResourceHeaderProvider: Sendable {
    private let configuration: AppConfiguration
    private let tokenStore: any TokenStore

    init(configuration: AppConfiguration, tokenStore: any TokenStore) {
        self.configuration = configuration
        self.tokenStore = tokenStore
    }

    func makeHeaders() async throws -> [String: String] {
        guard configuration.hasValidSeSACKey else {
            throw NetworkError.configuration(configuration.seSACKeyError ?? .missingSeSACKey)
        }
        guard let tokens = try await tokenStore.loadTokens() else {
            throw NetworkError.unauthorized
        }

        return [
            HTTPHeaderField.sesacKey: configuration.seSACKey,
            HTTPHeaderField.authorization: configuration.authorizationHeaderFormat.format(tokens.accessToken)
        ]
    }
}

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
        request.setValue(configuration.seSACKey, forHTTPHeaderField: HTTPHeaderField.sesacKey)

        try await applyAuthorizationHeaders(to: &request, policy: endpoint.authorizationPolicy)
        logRequestHeadersIfNeeded(request: request, endpoint: endpoint)

        for (field, value) in endpoint.headers {
            request.setValue(value, forHTTPHeaderField: field)
        }

        if let body = endpoint.body {
            request.httpBody = body.payload
            if request.value(forHTTPHeaderField: HTTPHeaderField.contentType) == nil {
                request.setValue(body.contentType, forHTTPHeaderField: HTTPHeaderField.contentType)
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
            let headers = try await ProtectedResourceHeaderProvider(
                configuration: configuration,
                tokenStore: tokenStore
            ).makeHeaders()
            apply(headers, to: &request)
        case .refreshToken:
            guard let tokens = try await tokenStore.loadTokens() else {
                throw NetworkError.refreshTokenExpired
            }
            request.setValue(
                configuration.authorizationHeaderFormat.format(tokens.accessToken),
                forHTTPHeaderField: HTTPHeaderField.authorization
            )
            request.setValue(tokens.refreshToken, forHTTPHeaderField: HTTPHeaderField.refreshToken)
        }
    }

    private func apply(_ headers: [String: String], to request: inout URLRequest) {
        for (field, value) in headers {
            request.setValue(value, forHTTPHeaderField: field)
        }
    }

    private func logRequestHeadersIfNeeded<ResponseDTO: Decodable & Sendable>(
        request: URLRequest,
        endpoint: Endpoint<ResponseDTO>
    ) {
#if DEBUG
        if isVideoStreamEndpoint(endpoint) {
            Logger.shared.debug(
                "[VideoAPI] request stream videoID=\(videoID(fromStreamEndpointPath: endpoint.path)) hasAuthorization=\(request.value(forHTTPHeaderField: HTTPHeaderField.authorization)?.isEmpty == false) hasSesacKey=\(request.value(forHTTPHeaderField: HTTPHeaderField.sesacKey)?.isEmpty == false)"
            )
        }

        guard endpoint.authorizationPolicy.requiresAuthenticatedSession else { return }

        let authorization = request.value(forHTTPHeaderField: HTTPHeaderField.authorization)
        let sesacKey = request.value(forHTTPHeaderField: HTTPHeaderField.sesacKey)
        Logger.shared.debugVerbose(
            "[Network] request method=\(endpoint.method.rawValue) url=\(request.url?.absoluteString ?? endpoint.path) hasAuthorization=\(authorization?.isEmpty == false) hasSesacKey=\(sesacKey?.isEmpty == false) accessTokenMasked=\(SensitiveLogRedactor.summary(for: authorization))"
        )
#endif
    }

    private func isVideoStreamEndpoint<ResponseDTO: Decodable & Sendable>(_ endpoint: Endpoint<ResponseDTO>) -> Bool {
        endpoint.method == .get
            && endpoint.path.hasPrefix("/v1/videos/")
            && endpoint.path.hasSuffix("/stream")
    }

    private func videoID(fromStreamEndpointPath path: String) -> String {
        path
            .replacingOccurrences(of: "/v1/videos/", with: "")
            .replacingOccurrences(of: "/stream", with: "")
    }
}
