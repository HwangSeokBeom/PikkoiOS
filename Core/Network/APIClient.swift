import Foundation

final class APIClient: APIClientProtocol {
    private let session: URLSession
    private let requestBuilder: RequestBuilder
    private let tokenRefreshCoordinator: TokenRefreshCoordinator
    private let responseCache = APIResponseCache()
    private let transportFailureThrottle = TransportFailureThrottle()

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
            let preparedResponse = try await executePreparedResponse(
                endpoint,
                didRetryTransport: didRetryTransport,
                didRetryAfterRefresh: didRetryAfterRefresh
            )
            return try decode(
                ResponseDTO.self,
                from: preparedResponse.data,
                response: preparedResponse.response,
                request: preparedResponse.request,
                statusCode: preparedResponse.response.statusCode,
                endpoint: endpoint
            )
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

    private func executePreparedResponse<ResponseDTO: Decodable & Sendable>(
        _ endpoint: Endpoint<ResponseDTO>,
        didRetryTransport: Bool,
        didRetryAfterRefresh: Bool
    ) async throws -> PreparedAPIResponse {
        let request = try await requestBuilder.build(for: endpoint)
        logRequestBodyIfNeeded(endpoint: endpoint, request: request)
        logProfileImageUploadRequestIfNeeded(endpoint: endpoint, request: request)
        logRequestStartedIfNeeded(endpoint: endpoint)

        if await transportFailureThrottle.shouldShortCircuitATSFailure(endpointPath: endpoint.path, url: request.url) {
#if DEBUG
            Logger.shared.warning(
                "[Network] ATS blocked insecure HTTP request. Check scoped ATS exception or use HTTPS. endpoint=\(endpoint.method.rawValue) \(endpoint.path) throttled=true"
            )
#endif
            throw NetworkError.configuration(.atsBlocked)
        }

        if let cacheDescriptor = cacheDescriptor(
            for: endpoint,
            request: request,
            didRetryAfterRefresh: didRetryAfterRefresh
        ) {
            if let cached = await responseCache.cachedResponse(
                for: cacheDescriptor.key,
                maxAge: cacheDescriptor.ttl
            ) {
                Logger.shared.debug("[Cache] hit key=\(cacheDescriptor.diagnosticKey)")
                Logger.shared.debug("[NetworkDedup] key=\(cacheDescriptor.diagnosticKey) action=skipped")
                return cached.preparedResponse(request: request)
            }

            Logger.shared.debug("[Cache] miss key=\(cacheDescriptor.diagnosticKey)")
            let taskResult = await responseCache.inFlightTask(for: cacheDescriptor.key) {
                Task<CachedAPIResponse, Error> {
                    let response = try await performNetworkRequest(
                        endpoint,
                        request: request,
                        didRetryTransport: didRetryTransport,
                        didRetryAfterRefresh: didRetryAfterRefresh
                    )
                    return CachedAPIResponse(
                        data: response.data,
                        url: response.response.url ?? request.url,
                        statusCode: response.response.statusCode,
                        headers: stringHeaders(from: response.response)
                    )
                }
            }

            if taskResult.isNew {
                Logger.shared.debug("[NetworkDedup] key=\(cacheDescriptor.diagnosticKey) action=new")
            } else {
                Logger.shared.debug("[NetworkDedup] key=\(cacheDescriptor.diagnosticKey) action=reuse")
            }

            do {
                let cachedResponse = try await taskResult.task.value
                await responseCache.store(cachedResponse, for: cacheDescriptor.key)
                await responseCache.removeInFlightTask(for: cacheDescriptor.key)
                return cachedResponse.preparedResponse(request: request)
            } catch {
                await responseCache.removeInFlightTask(for: cacheDescriptor.key)
                throw error
            }
        }

        return try await performNetworkRequest(
            endpoint,
            request: request,
            didRetryTransport: didRetryTransport,
            didRetryAfterRefresh: didRetryAfterRefresh
        )
    }

    private func performNetworkRequest<ResponseDTO: Decodable & Sendable>(
        _ endpoint: Endpoint<ResponseDTO>,
        request: URLRequest,
        didRetryTransport: Bool,
        didRetryAfterRefresh: Bool
    ) async throws -> PreparedAPIResponse {
        let requestID = UUID().uuidString
        let startTime = CFAbsoluteTimeGetCurrent()
        Logger.shared.debug(
            "[Network] request method=\(endpoint.method.rawValue) path=\(endpoint.path) requestID=\(requestID)"
        )

        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw NetworkError.transport
            }
            let durationMs = Int((CFAbsoluteTimeGetCurrent() - startTime) * 1_000)
            Logger.shared.debug(
                "[Network] response path=\(endpoint.path) status=\(httpResponse.statusCode) durationMs=\(durationMs) requestID=\(requestID)"
            )
            logProfileImageUploadResponseIfNeeded(
                endpoint: endpoint,
                statusCode: httpResponse.statusCode,
                durationMs: durationMs,
                data: data
            )

            switch httpResponse.statusCode {
            case 200..<300:
                return PreparedAPIResponse(data: data, response: httpResponse, request: request)
            case 401 where shouldAttemptRefresh(for: endpoint, didRetryAfterRefresh: didRetryAfterRefresh),
                 419 where shouldAttemptRefresh(for: endpoint, didRetryAfterRefresh: didRetryAfterRefresh):
                _ = try await tokenRefreshCoordinator.refreshTokens()
                return try await executePreparedResponse(
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
            throw error
        } catch {
            if error is CancellationError || Task.isCancelled {
                throw CancellationError()
            }

            if let urlError = error as? URLError,
               urlError.code == .cancelled {
                throw CancellationError()
            }

            if let urlError = error as? URLError,
               urlError.isATSBlocked {
                await transportFailureThrottle.recordATSFailure(endpointPath: endpoint.path, url: request.url)
#if DEBUG
                Logger.shared.warning(
                    "[Network] ATS blocked insecure HTTP request. Check scoped ATS exception or use HTTPS. endpoint=\(endpoint.method.rawValue) \(endpoint.path) url=\(diagnosticURL(request.url))"
                )
#endif
                throw NetworkError.configuration(.atsBlocked)
            }

            if endpoint.method.isTransportRetryEligible,
               !didRetryTransport,
               error is URLError {
                return try await executePreparedResponse(
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

    private func logProfileImageUploadRequestIfNeeded<ResponseDTO: Decodable & Sendable>(
        endpoint: Endpoint<ResponseDTO>,
        request: URLRequest
    ) {
#if DEBUG
        guard endpoint.path == "/v1/users/profile/image",
              endpoint.method == .post else {
            return
        }

        let diagnostics = multipartFileDiagnostics(from: request)
        Logger(category: "ProfileImageUpload").debug(
            "[ProfileImageUpload] request path=/v1/users/profile/image field=\(diagnostics.fieldName) filename=\(diagnostics.fileName) mime=\(diagnostics.mimeType) byteSize=\(diagnostics.byteSize) underLimit=\(diagnostics.byteSize <= 1 * 1024 * 1024) hasAuthorization=\(request.value(forHTTPHeaderField: HTTPHeaderField.authorization)?.isEmpty == false) hasSesacKey=\(request.value(forHTTPHeaderField: HTTPHeaderField.sesacKey)?.isEmpty == false)"
        )
#endif
    }

    private func logProfileImageUploadResponseIfNeeded<ResponseDTO: Decodable & Sendable>(
        endpoint: Endpoint<ResponseDTO>,
        statusCode: Int,
        durationMs: Int,
        data: Data
    ) {
#if DEBUG
        guard endpoint.path == "/v1/users/profile/image",
              endpoint.method == .post else {
            return
        }

        Logger(category: "ProfileImageUpload").debug(
            "[ProfileImageUpload] response status=\(statusCode) durationMs=\(durationMs) responseProfileImage=\(profileImagePath(from: data) ?? "nil")"
        )
        if (200..<300).contains(statusCode),
           let profileImage = profileImagePath(from: data) {
            Logger(category: "ProfileImage").debug("[ProfileImage] upload success profileImage=\(profileImage)")
        }
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

    private func cacheDescriptor<ResponseDTO: Decodable & Sendable>(
        for endpoint: Endpoint<ResponseDTO>,
        request: URLRequest,
        didRetryAfterRefresh: Bool
    ) -> APICacheDescriptor? {
        guard endpoint.method == .get,
              endpoint.body == nil,
              endpoint.authorizationPolicy != .refreshToken,
              endpoint.cachePolicy == .automatic,
              !didRetryAfterRefresh,
              !isVideoStreamEndpoint(endpoint),
              let url = request.url,
              let ttl = cacheTTL(for: endpoint) else {
            return nil
        }

        let authorizationHash = request
            .value(forHTTPHeaderField: HTTPHeaderField.authorization)
            .map { String($0.hashValue) } ?? "none"
        let responseType = String(describing: ResponseDTO.self)
        let key = [
            endpoint.method.rawValue,
            url.absoluteString,
            "authHash=\(authorizationHash)",
            "response=\(responseType)"
        ].joined(separator: "|")
        let queryHash = url.query.map { String($0.hashValue) } ?? "none"
        let diagnosticKey = "\(endpoint.method.rawValue) \(endpoint.path) queryHash=\(queryHash) response=\(responseType)"

        return APICacheDescriptor(key: key, diagnosticKey: diagnosticKey, ttl: ttl)
    }

    private func cacheTTL<ResponseDTO: Decodable & Sendable>(
        for endpoint: Endpoint<ResponseDTO>
    ) -> TimeInterval? {
        guard endpoint.method == .get else { return nil }

        if endpoint.path == "/v1/videos" {
            return 60
        }

        if endpoint.path.hasPrefix("/v1/banners") {
            return 300
        }

        if endpoint.path.contains("/popular-stores")
            || endpoint.path.contains("/searches-popular")
            || endpoint.path.hasPrefix("/v1/stores") {
            return 60
        }

        if endpoint.path.hasPrefix("/v1/orders")
            || endpoint.path.hasPrefix("/v1/notifications")
            || endpoint.path.hasPrefix("/v1/carts")
            || endpoint.path.hasPrefix("/v1/users/me") {
            return 8
        }

        if endpoint.path.hasPrefix("/v1/posts")
            || endpoint.path.hasPrefix("/v1/comments") {
            return 12
        }

        return endpoint.authorizationPolicy.requiresAuthenticatedSession ? 15 : 60
    }

    private func stringHeaders(from response: HTTPURLResponse) -> [String: String] {
        response.allHeaderFields.reduce(into: [String: String]()) { result, pair in
            guard let key = pair.key as? String else { return }
            result[key] = "\(pair.value)"
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

    private func multipartFileDiagnostics(from request: URLRequest) -> (fieldName: String, fileName: String, mimeType: String, byteSize: Int) {
        guard let body = request.httpBody,
              let contentType = request.value(forHTTPHeaderField: HTTPHeaderField.contentType),
              let boundary = contentType.components(separatedBy: "boundary=").last,
              let headerEndRange = body.range(of: Data("\r\n\r\n".utf8)) else {
            return ("unknown", "unknown", "unknown", request.httpBody?.count ?? 0)
        }

        let headerData = body[..<headerEndRange.lowerBound]
        let header = String(decoding: headerData, as: UTF8.self)
        let contentStart = headerEndRange.upperBound
        let closingBoundary = Data("\r\n--\(boundary)--".utf8)
        let fileByteSize: Int
        if let closingRange = body.range(of: closingBoundary, in: contentStart..<body.endIndex) {
            fileByteSize = max(0, closingRange.lowerBound - contentStart)
        } else {
            fileByteSize = max(0, body.count - contentStart)
        }

        return (
            quotedValue(named: "name", in: header) ?? "unknown",
            quotedValue(named: "filename", in: header) ?? "unknown",
            headerLineValue(named: "Content-Type", in: header) ?? "unknown",
            fileByteSize
        )
    }

    private func quotedValue(named name: String, in string: String) -> String? {
        let marker = "\(name)=\""
        guard let startRange = string.range(of: marker) else { return nil }
        let valueStart = startRange.upperBound
        guard let endRange = string[valueStart...].range(of: "\"") else { return nil }
        return String(string[valueStart..<endRange.lowerBound])
    }

    private func headerLineValue(named name: String, in string: String) -> String? {
        string
            .components(separatedBy: "\r\n")
            .first { $0.lowercased().hasPrefix("\(name.lowercased()):") }?
            .split(separator: ":", maxSplits: 1)
            .last
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
    }

    private func profileImagePath(from data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let profileImage = object["profileImage"] as? String else {
            return nil
        }
        return profileImage
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

    private func diagnosticURL(_ url: URL?) -> String {
        guard let url,
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return "<invalid-url>"
        }
        components.query = nil
        components.fragment = nil
        return components.string ?? url.path
    }
}

private extension URLError {
    var isATSBlocked: Bool {
        code == .appTransportSecurityRequiresSecureConnection || errorCode == -1022
    }
}

private struct APICacheDescriptor: Sendable {
    let key: String
    let diagnosticKey: String
    let ttl: TimeInterval
}

private struct PreparedAPIResponse: Sendable {
    let data: Data
    let response: HTTPURLResponse
    let request: URLRequest
}

private struct CachedAPIResponse: Sendable {
    let data: Data
    let url: URL?
    let statusCode: Int
    let headers: [String: String]

    func preparedResponse(request: URLRequest) -> PreparedAPIResponse {
        let responseURL = url ?? request.url ?? URL(string: "https://invalid.local")!
        let response = HTTPURLResponse(
            url: responseURL,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: headers
        )!
        return PreparedAPIResponse(data: data, response: response, request: request)
    }
}

private actor APIResponseCache {
    private struct Entry {
        let response: CachedAPIResponse
        let storedAt: Date
    }

    private var storage: [String: Entry] = [:]
    private var inFlightTasks: [String: Task<CachedAPIResponse, Error>] = [:]
    private let maxEntryCount = 120

    func cachedResponse(for key: String, maxAge: TimeInterval) -> CachedAPIResponse? {
        guard let entry = storage[key] else {
            return nil
        }

        if Date().timeIntervalSince(entry.storedAt) <= maxAge {
            return entry.response
        }

        storage[key] = nil
        return nil
    }

    func store(_ response: CachedAPIResponse, for key: String) {
        storage[key] = Entry(response: response, storedAt: Date())
        trimIfNeeded()
    }

    func inFlightTask(
        for key: String,
        create: @Sendable () -> Task<CachedAPIResponse, Error>
    ) -> (task: Task<CachedAPIResponse, Error>, isNew: Bool) {
        if let task = inFlightTasks[key] {
            return (task, false)
        }
        let task = create()
        inFlightTasks[key] = task
        return (task, true)
    }

    func removeInFlightTask(for key: String) {
        inFlightTasks[key] = nil
    }

    private func trimIfNeeded() {
        guard storage.count > maxEntryCount else { return }
        let overflowCount = storage.count - maxEntryCount
        let keysToRemove = storage
            .sorted { $0.value.storedAt < $1.value.storedAt }
            .prefix(overflowCount)
            .map(\.key)
        for key in keysToRemove {
            storage[key] = nil
        }
    }
}

private actor TransportFailureThrottle {
    private var atsFailedEndpoints: [String: Date] = [:]
    private let shortCircuitWindow: TimeInterval = 30

    func shouldShortCircuitATSFailure(endpointPath: String, url: URL?) -> Bool {
        let key = makeKey(endpointPath: endpointPath, url: url)
        guard let failedAt = atsFailedEndpoints[key] else {
            return false
        }

        if Date().timeIntervalSince(failedAt) <= shortCircuitWindow {
            return true
        }

        atsFailedEndpoints[key] = nil
        return false
    }

    func recordATSFailure(endpointPath: String, url: URL?) {
        atsFailedEndpoints[makeKey(endpointPath: endpointPath, url: url)] = Date()
    }

    private func makeKey(endpointPath: String, url: URL?) -> String {
        guard let url,
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return endpointPath
        }
        components.query = nil
        components.fragment = nil
        return components.string ?? endpointPath
    }
}
