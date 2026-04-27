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
                let mappedError = HTTPStatusMapper.map(statusCode: httpResponse.statusCode, data: data)
                if httpResponse.statusCode == 444 {
                    Logger.shared.error(
                        "Received 444 for \(endpoint.method.rawValue) \(endpoint.path). Check Swagger path/method alignment."
                    )
                }
                Logger.shared.warning(
                    "HTTP request failed. endpoint=\(endpoint.method.rawValue) \(endpoint.path) statusCode=\(httpResponse.statusCode) message=\(mappedError.localizedDescription)"
                )
                switch mappedError {
                case .unauthorized, .accessTokenExpired, .refreshTokenExpired, .forbidden:
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
