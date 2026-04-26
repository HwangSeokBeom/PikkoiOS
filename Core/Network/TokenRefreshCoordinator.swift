import Foundation

actor TokenRefreshCoordinator {
    private let session: URLSession
    private let requestBuilder: RequestBuilder
    private let tokenStore: any TokenStore
    private let refreshPath: String
    private let refreshMethod: HTTPMethod

    private var inFlightRefreshTask: Task<StoredTokens, Error>?

    init(
        session: URLSession,
        requestBuilder: RequestBuilder,
        tokenStore: any TokenStore,
        refreshPath: String = "/v1/auth/refresh",
        refreshMethod: HTTPMethod = .get
    ) {
        self.session = session
        self.requestBuilder = requestBuilder
        self.tokenStore = tokenStore
        self.refreshPath = refreshPath
        self.refreshMethod = refreshMethod
    }

    func refreshTokens() async throws -> StoredTokens {
        if let inFlightRefreshTask {
            return try await inFlightRefreshTask.value
        }

        let refreshTask = Task<StoredTokens, Error> {
            try await performRefresh()
        }
        inFlightRefreshTask = refreshTask

        do {
            let refreshedTokens = try await refreshTask.value
            inFlightRefreshTask = nil
            return refreshedTokens
        } catch {
            inFlightRefreshTask = nil
            throw error
        }
    }

    func invalidateSession() async {
        do {
            try await tokenStore.clearTokens()
        } catch {
            Logger.shared.warning("TokenStore clear failed during invalidation: \(error.localizedDescription)")
        }

        NotificationCenter.default.post(name: .pikkoSessionDidInvalidate, object: nil)
    }

    private func performRefresh() async throws -> StoredTokens {
        let endpoint = Endpoint<RefreshTokenResponseDTO>(
            path: refreshPath,
            method: refreshMethod,
            timeout: .default,
            authorizationPolicy: .refreshToken
        )
        let request: URLRequest
        do {
            request = try await requestBuilder.build(for: endpoint)
        } catch let error as NetworkError {
            if error.shouldInvalidateSessionImmediately {
                await invalidateSession()
            }
            throw error
        }

        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw NetworkError.transport
            }

            switch httpResponse.statusCode {
            case 200..<300:
                let payload = try NetworkCoding.makeJSONDecoder().decode(RefreshTokenResponseDTO.self, from: data)
                guard let existingTokens = try await tokenStore.loadTokens() else {
                    throw NetworkError.refreshTokenExpired
                }

                let refreshedTokens = StoredTokens(
                    accessToken: payload.accessToken,
                    refreshToken: payload.refreshToken ?? existingTokens.refreshToken
                )
                try await tokenStore.saveTokens(refreshedTokens)
                NotificationCenter.default.post(
                    name: .pikkoTokensDidRefresh,
                    object: nil,
                    userInfo: [
                        NetworkSessionNotificationUserInfoKey.accessToken: refreshedTokens.accessToken,
                        NetworkSessionNotificationUserInfoKey.refreshToken: refreshedTokens.refreshToken
                    ]
                )
                return refreshedTokens
            default:
                let mappedError = HTTPStatusMapper.map(statusCode: httpResponse.statusCode, data: data)
                switch mappedError {
                case .unauthorized, .forbidden, .refreshTokenExpired, .accessTokenExpired:
                    await invalidateSession()
                    throw NetworkError.refreshTokenExpired
                default:
                    throw mappedError
                }
            }
        } catch let error as NetworkError {
            throw error
        } catch {
            throw NetworkError.transport
        }
    }
}
