import Foundation

final class APIClient: APIClientProtocol {
    private let session: URLSession
    private let requestBuilder: RequestBuilder
    private let tokenRefreshCoordinator: TokenRefreshCoordinator

    init(
        session: URLSession,
        requestBuilder: RequestBuilder,
        tokenRefreshCoordinator: TokenRefreshCoordinator
    ) {
        self.session = session
        self.requestBuilder = requestBuilder
        self.tokenRefreshCoordinator = tokenRefreshCoordinator
    }

    func execute<ResponseDTO: Decodable & Sendable>(
        _ endpoint: Endpoint<ResponseDTO>
    ) async throws -> ResponseDTO {
        try await execute(endpoint, didRetryTransport: false, didRetryAfterRefresh: false)
    }

    private func execute<ResponseDTO: Decodable & Sendable>(
        _ endpoint: Endpoint<ResponseDTO>,
        didRetryTransport: Bool,
        didRetryAfterRefresh: Bool
    ) async throws -> ResponseDTO {
        do {
            let request = try await requestBuilder.build(for: endpoint)
            logRequestBodyIfNeeded(endpoint: endpoint, request: request)
            logRequestStartedIfNeeded(endpoint: endpoint)
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw NetworkError.transport
            }

            switch httpResponse.statusCode {
            case 200..<300:
                return try decode(
                    ResponseDTO.self,
                    from: data,
                    statusCode: httpResponse.statusCode,
                    endpoint: endpoint
                )
            case 401 where shouldAttemptRefresh(for: endpoint, didRetryAfterRefresh: didRetryAfterRefresh),
                 419 where shouldAttemptRefresh(for: endpoint, didRetryAfterRefresh: didRetryAfterRefresh):
                _ = try await tokenRefreshCoordinator.refreshTokens()
                return try await execute(
                    endpoint,
                    didRetryTransport: didRetryTransport,
                    didRetryAfterRefresh: true
                )
            default:
                let serverMessage = HTTPStatusMapper.message(statusCode: httpResponse.statusCode, data: data)
                let mappedError = HTTPStatusMapper.map(statusCode: httpResponse.statusCode, data: data)
                if httpResponse.statusCode == 444 {
                    Logger.shared.error(
                        "Received 444 for \(endpoint.method.rawValue) \(endpoint.path). Check Swagger path/method alignment."
                    )
                }
                Logger.shared.warning(
                    "HTTP request failed. endpoint=\(endpoint.method.rawValue) \(endpoint.path) statusCode=\(httpResponse.statusCode) serverMessage=\(serverMessage) mappedMessage=\(mappedError.localizedDescription)"
                )
                logFailurePayloadIfNeeded(endpoint: endpoint, statusCode: httpResponse.statusCode, data: data)
                if endpoint.path == "/v1/users/login/kakao" {
                    Logger.shared.warning(
                        "[Auth] social login failed provider=kakao endpoint=\(endpoint.path) statusCode=\(httpResponse.statusCode) serverMessage=\(serverMessage)"
                    )
                }
                switch mappedError {
                case .unauthorized, .authenticationFailed, .accessTokenExpired, .refreshTokenExpired, .forbidden:
                    await tokenRefreshCoordinator.invalidateSession()
                default:
                    break
                }
                throw mappedError
            }
        } catch let error as NetworkError {
            if endpoint.authorizationPolicy.requiresAuthenticatedSession,
               error.shouldInvalidateSessionImmediately {
                await tokenRefreshCoordinator.invalidateSession()
            }
            throw error
        } catch {
            if error is CancellationError || Task.isCancelled {
                throw CancellationError()
            }

            if let urlError = error as? URLError,
               urlError.code == .cancelled {
                throw CancellationError()
            }

            if endpoint.method.isTransportRetryEligible,
               !didRetryTransport,
               error is URLError {
                return try await execute(
                    endpoint,
                    didRetryTransport: true,
                    didRetryAfterRefresh: didRetryAfterRefresh
                )
            }

            throw NetworkError.transport
        }
    }

    private func logRequestBodyIfNeeded<ResponseDTO: Decodable & Sendable>(
        endpoint: Endpoint<ResponseDTO>,
        request: URLRequest
    ) {
#if DEBUG
        guard endpoint.path == "/v1/users/login/kakao",
              endpoint.method == .post else {
            return
        }

        let jsonObject = request.httpBody.flatMap {
            try? JSONSerialization.jsonObject(with: $0) as? [String: Any]
        }
        let oauthToken = jsonObject?["oauthToken"] as? String
        let deviceToken = jsonObject?["deviceToken"] as? String

        Logger.shared.debug(
            "[Auth] kakao login request body endpoint=/v1/users/login/kakao oauthTokenSummary=\(SensitiveLogRedactor.summary(for: oauthToken)) deviceTokenSummary=\(SensitiveLogRedactor.summary(for: deviceToken))"
        )
#endif
    }

    private func logRequestStartedIfNeeded<ResponseDTO: Decodable & Sendable>(
        endpoint: Endpoint<ResponseDTO>
    ) {
#if DEBUG
        guard endpoint.path == "/v1/users/login/kakao",
              endpoint.method == .post else {
            return
        }

        Logger.shared.debug("HTTP request started endpoint=POST /v1/users/login/kakao")
#endif
    }

    private func shouldAttemptRefresh<ResponseDTO: Decodable & Sendable>(
        for endpoint: Endpoint<ResponseDTO>,
        didRetryAfterRefresh: Bool
    ) -> Bool {
        guard !didRetryAfterRefresh else { return false }

        switch endpoint.authorizationPolicy {
        case .accessToken, .fileAuthorized:
            return true
        case .none, .refreshToken:
            return false
        }
    }

    private func logFailurePayloadIfNeeded<ResponseDTO: Decodable & Sendable>(
        endpoint: Endpoint<ResponseDTO>,
        statusCode: Int,
        data: Data
    ) {
#if DEBUG
        guard endpoint.authorizationPolicy.requiresAuthenticatedSession else { return }
        let payloadSnippet = String(data: data.prefix(512), encoding: .utf8) ?? "<non-utf8>"
        Logger.shared.warning(
            "[Network] response failed statusCode=\(statusCode) endpoint=\(endpoint.method.rawValue) \(endpoint.path) body=\(payloadSnippet)"
        )
#endif
    }

    private func decode<ResponseDTO: Decodable & Sendable>(
        _ type: ResponseDTO.Type,
        from data: Data,
        statusCode: Int,
        endpoint: Endpoint<ResponseDTO>
    ) throws -> ResponseDTO {
        if ResponseDTO.self == EmptyResponse.self {
            return EmptyResponse() as! ResponseDTO
        }

        if data.isEmpty {
            throw NetworkError.decoding
        }

        do {
            return try NetworkCoding.makeJSONDecoder().decode(ResponseDTO.self, from: data)
        } catch {
            let payloadSnippet = String(data: data.prefix(512), encoding: .utf8) ?? "<non-utf8>"
            Logger.shared.error(
                "Decoding failed for \(endpoint.method.rawValue) \(endpoint.path) into \(String(describing: ResponseDTO.self)). payload=\(payloadSnippet)"
            )
            throw NetworkError.decoding
        }
    }
}
