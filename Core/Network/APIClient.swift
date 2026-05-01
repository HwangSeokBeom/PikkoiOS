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
                    response: httpResponse,
                    request: request,
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
                logDomainFailureIfNeeded(
                    endpoint: endpoint,
                    request: request,
                    response: httpResponse,
                    statusCode: httpResponse.statusCode,
                    serverMessage: serverMessage,
                    data: data
                )
                if endpoint.path == "/v1/users/login/kakao" {
                    Logger.shared.warning(
                        "[Auth] social login failed provider=kakao endpoint=\(endpoint.path) statusCode=\(httpResponse.statusCode) serverMessage=\(serverMessage)"
                    )
                }
                if httpResponse.statusCode == 403, isVideoStreamEndpoint(endpoint) {
                    Logger.shared.warning(
                        "[Network] forbidden endpoint=\(endpoint.method.rawValue) \(endpoint.path) action=showError keepSession=true"
                    )
                }
                switch mappedError {
                case .unauthorized, .authenticationFailed, .accessTokenExpired, .refreshTokenExpired:
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
        if endpoint.path == "/v1/notifications/push",
           endpoint.method == .post {
            Logger.shared.debug(
                "[PushRequest] endpoint=POST /v1/notifications/push bodyKeys=\(jsonBodyKeys(from: request.httpBody).joined(separator: ",")) hasAuthorization=\(request.value(forHTTPHeaderField: "Authorization")?.isEmpty == false) hasSesacKey=\(request.value(forHTTPHeaderField: "SesacKey")?.isEmpty == false)"
            )
            return
        }

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

    private func isVideoStreamEndpoint<ResponseDTO: Decodable & Sendable>(_ endpoint: Endpoint<ResponseDTO>) -> Bool {
        endpoint.method == .get
            && endpoint.path.hasPrefix("/v1/videos/")
            && endpoint.path.hasSuffix("/stream")
    }

    private func logFailurePayloadIfNeeded<ResponseDTO: Decodable & Sendable>(
        endpoint: Endpoint<ResponseDTO>,
        statusCode: Int,
        data: Data
    ) {
#if DEBUG
        guard endpoint.authorizationPolicy.requiresAuthenticatedSession else { return }
        let payloadSnippet = String(data: data.prefix(512), encoding: .utf8) ?? "<non-utf8>"
        Logger.shared.debugVerbose(
            "[Network] response failed statusCode=\(statusCode) endpoint=\(endpoint.method.rawValue) \(endpoint.path) body=\(payloadSnippet)"
        )
#endif
    }

    private func logDomainFailureIfNeeded<ResponseDTO: Decodable & Sendable>(
        endpoint: Endpoint<ResponseDTO>,
        request: URLRequest,
        response: HTTPURLResponse,
        statusCode: Int,
        serverMessage: String,
        data: Data
    ) {
#if DEBUG
        let payloadSnippet = String(data: data.prefix(512), encoding: .utf8) ?? "<non-utf8>"
        let requestBody = request.httpBody.flatMap {
            String(data: $0.prefix(512), encoding: .utf8)
        } ?? "{}"

        if endpoint.path == "/v1/payments/validation" {
            let orderCode = paymentValidationOrderCode(from: request.httpBody) ?? "nil"
            Logger.shared.warning(
                "[PaymentValidation] failed orderCode=\(orderCode) statusCode=\(statusCode) message=\(serverMessage) body=\(maskedPaymentValidationBody(from: request.httpBody))"
            )
        } else if endpoint.method == .put, endpoint.path.hasPrefix("/v1/orders/") {
            Logger.shared.warning(
                "[OrderStatus] failed orderCode=\(endpoint.path.replacingOccurrences(of: "/v1/orders/", with: "")) statusCode=\(statusCode) serverMessage=\(serverMessage) body=\(requestBody) responseBody=\(payloadSnippet)"
            )
        } else if endpoint.path == "/v1/notifications/push" {
            Logger.shared.warning(
                "[PushRequest] failed endpoint=POST /v1/notifications/push statusCode=\(statusCode) serverMessage=\(serverMessage) bodyKeys=\(jsonBodyKeys(from: request.httpBody).joined(separator: ","))"
            )
        } else if endpoint.path == "/v1/videos" {
            Logger.shared.error(
                "[VideoAPI] list failed status=\(statusCode) contentType=\(response.value(forHTTPHeaderField: "Content-Type") ?? "nil") contentLength=\(data.count) firstBytesHex=\(firstBytesHex(data)) endpoint=\(endpoint.method.rawValue) \(endpoint.path) hasAuthorization=\(request.value(forHTTPHeaderField: "Authorization")?.isEmpty == false) hasSesacKey=\(request.value(forHTTPHeaderField: "SesacKey")?.isEmpty == false) decoding=non2xx"
            )
        }
#endif
    }

    private func jsonBodyKeys(from data: Data?) -> [String] {
        guard let data,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return []
        }
        return object.keys.sorted()
    }

    private func maskedPaymentValidationBody(from data: Data?) -> String {
        guard let data,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return "{}"
        }
        let impUID = object["imp_uid"] as? String
        return "{\"imp_uid\":\"<present:\((impUID?.isEmpty == false))>\"}"
    }

    private func paymentValidationOrderCode(from data: Data?) -> String? {
        guard let data,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return object["order_code"] as? String ?? object["orderCode"] as? String
    }

    private func decode<ResponseDTO: Decodable & Sendable>(
        _ type: ResponseDTO.Type,
        from data: Data,
        response: HTTPURLResponse,
        request: URLRequest,
        statusCode: Int,
        endpoint: Endpoint<ResponseDTO>
    ) throws -> ResponseDTO {
        if ResponseDTO.self == EmptyResponse.self {
            return EmptyResponse() as! ResponseDTO
        }

        if data.isEmpty {
            throw NetworkError.decoding
        }

#if DEBUG
        logSuccessfulPayloadShapeIfNeeded(endpoint: endpoint, statusCode: statusCode, data: data)
#endif

        do {
            return try NetworkCoding.makeJSONDecoder().decode(ResponseDTO.self, from: data)
        } catch {
            logDecodingFailure(
                error: error,
                data: data,
                response: response,
                request: request,
                endpoint: endpoint,
                responseType: ResponseDTO.self
            )
            throw NetworkError.decoding
        }
    }

#if DEBUG
    private func logSuccessfulPayloadShapeIfNeeded<ResponseDTO: Decodable & Sendable>(
        endpoint: Endpoint<ResponseDTO>,
        statusCode: Int,
        data: Data
    ) {
        guard isVideoStreamEndpoint(endpoint),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return
        }

        Logger.shared.debug(
            "[VideoAPI] raw stream response status=\(statusCode) keys=\(object.keys.sorted().joined(separator: ","))"
        )
    }
#endif

    private func logDecodingFailure<ResponseDTO: Decodable & Sendable>(
        error: Error,
        data: Data,
        response: HTTPURLResponse,
        request: URLRequest,
        endpoint: Endpoint<ResponseDTO>,
        responseType: ResponseDTO.Type
    ) {
        let decodingSummary = decodingErrorSummary(error)

        if endpoint.path == "/v1/videos" {
            Logger.shared.error(
                "[VideoAPI] list failed status=\(response.statusCode) contentType=\(response.value(forHTTPHeaderField: "Content-Type") ?? "nil") contentLength=\(data.count) firstBytesHex=\(firstBytesHex(data)) endpoint=\(endpoint.method.rawValue) \(endpoint.path) hasAuthorization=\(request.value(forHTTPHeaderField: "Authorization")?.isEmpty == false) hasSesacKey=\(request.value(forHTTPHeaderField: "SesacKey")?.isEmpty == false) decoding=\(decodingSummary)"
            )
            return
        }

        let payloadSnippet = String(data: data.prefix(512), encoding: .utf8) ?? "<non-utf8>"
        Logger.shared.error(
            "Decoding failed for \(endpoint.method.rawValue) \(endpoint.path) into \(String(describing: responseType)). decoding=\(decodingSummary) payload=\(payloadSnippet)"
        )
    }

    private func decodingErrorSummary(_ error: Error) -> String {
        guard let decodingError = error as? DecodingError else {
            return error.localizedDescription
        }

        switch decodingError {
        case .typeMismatch(let type, let context):
            return "typeMismatch type=\(type) path=\(codingPathString(context.codingPath)) description=\(context.debugDescription)"
        case .valueNotFound(let type, let context):
            return "valueNotFound type=\(type) path=\(codingPathString(context.codingPath)) description=\(context.debugDescription)"
        case .keyNotFound(let key, let context):
            return "keyNotFound key=\(key.stringValue) path=\(codingPathString(context.codingPath)) description=\(context.debugDescription)"
        case .dataCorrupted(let context):
            return "dataCorrupted path=\(codingPathString(context.codingPath)) description=\(context.debugDescription)"
        @unknown default:
            return decodingError.localizedDescription
        }
    }

    private func codingPathString(_ codingPath: [CodingKey]) -> String {
        let path = codingPath.map(\.stringValue).joined(separator: ".")
        return path.isEmpty ? "<root>" : path
    }

    private func firstBytesHex(_ data: Data) -> String {
        data.prefix(64).map { String(format: "%02x", $0) }.joined()
    }
}
