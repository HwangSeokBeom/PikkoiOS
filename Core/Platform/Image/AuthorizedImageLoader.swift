import Foundation

protocol AuthorizedImageLoading: Sendable {
    func imageData(for path: String) async throws -> Data
    func cachedImageData(for path: String) async throws -> Data?
    func removeCachedImage(for path: String) async throws
}

enum ImageLoadError: Error, LocalizedError, Equatable, Sendable {
    case notFoundOrBlocked

    var errorDescription: String? {
        switch self {
        case .notFoundOrBlocked:
            return "이미지를 불러올 수 없어요."
        }
    }
}

actor AuthorizedImageLoader: AuthorizedImageLoading {
    private let logger = Logger(category: "AuthorizedImageLoader")
    private let session: URLSession
    private let requestBuilder: RequestBuilder
    private let tokenRefreshCoordinator: TokenRefreshCoordinator
    private let fileURLResolver: any AuthorizedFileURLResolving
    private let imageCache: ImageCache

    private var inFlightTasks: [URL: Task<Data, Error>] = [:]
    private var failedURLCache: [URL: Date] = [:]
    private var loggedFailedURLs: Set<URL> = []
    private var loggedFallbackKeys = Set<String>()
    private let failedURLCacheTTL: TimeInterval = 300

    init(
        session: URLSession,
        requestBuilder: RequestBuilder,
        tokenRefreshCoordinator: TokenRefreshCoordinator,
        fileURLResolver: any AuthorizedFileURLResolving,
        imageCache: ImageCache
    ) {
        self.session = session
        self.requestBuilder = requestBuilder
        self.tokenRefreshCoordinator = tokenRefreshCoordinator
        self.fileURLResolver = fileURLResolver
        self.imageCache = imageCache
    }

    func imageData(for path: String) async throws -> Data {
        let url: URL
        do {
            url = try fileURLResolver.resolveURL(from: path)
        } catch {
            logger.warning("Image URL resolution failed. path=\(path) error=\(error.localizedDescription)")
            throw error
        }

        if let cachedData = await imageCache.data(for: url) {
            return cachedData
        }

        if let failedAt = failedURLCache[url], Date().timeIntervalSince(failedAt) < failedURLCacheTTL {
            throw ImageLoadError.notFoundOrBlocked
        } else {
            failedURLCache[url] = nil
        }

        if let inFlightTask = inFlightTasks[url] {
            return try await inFlightTask.value
        }

        let task = Task<Data, Error> {
            try await fetchImageData(from: url, didRetryAfterRefresh: false)
        }
        inFlightTasks[url] = task

        do {
            let data = try await task.value
            await imageCache.insert(data, for: url)
            inFlightTasks[url] = nil
            return data
        } catch {
            inFlightTasks[url] = nil
            if case .notFoundOrBlocked = error as? ImageLoadError {
                failedURLCache[url] = Date()
                logFailedURLOnce(url: url, statusDescription: error.localizedDescription)
            } else if hasLoggedFallback(for: url) {
                // The placeholder fallback warning was already emitted at the HTTP status boundary.
            } else {
                logger.warning("Image load failed. url=\(url.absoluteString) error=\(error.localizedDescription)")
            }
            throw error
        }
    }

    func cachedImageData(for path: String) async throws -> Data? {
        let url = try fileURLResolver.resolveURL(from: path)
        return await imageCache.data(for: url)
    }

    func removeCachedImage(for path: String) async throws {
        let url = try fileURLResolver.resolveURL(from: path)
        await imageCache.removeValue(for: url)
    }

    private func fetchImageData(from url: URL, didRetryAfterRefresh: Bool) async throws -> Data {
        let endpoint = Endpoint<EmptyResponse>(
            path: url.absoluteString,
            method: .get,
            timeout: .default,
            authorizationPolicy: .fileAuthorized
        )
        let request: URLRequest
        do {
            request = try await requestBuilder.build(for: endpoint)
        } catch let error as NetworkError {
            if error.shouldInvalidateSessionImmediately {
                await tokenRefreshCoordinator.invalidateSession()
            }
            throw error
        }

        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw NetworkError.transport
            }
#if DEBUG
            logger.debug(
                "Image request completed. url=\(url.absoluteString) status=\(httpResponse.statusCode) hasAuthorization=\(request.value(forHTTPHeaderField: "Authorization")?.isEmpty == false) hasSesacKey=\(request.value(forHTTPHeaderField: "SesacKey")?.isEmpty == false)"
            )
#endif

            switch httpResponse.statusCode {
            case 200..<300:
                return data
            case 401 where !didRetryAfterRefresh,
                 419 where !didRetryAfterRefresh:
                _ = try await tokenRefreshCoordinator.refreshTokens()
                return try await fetchImageData(from: url, didRetryAfterRefresh: true)
            case 444:
                logFallbackPlaceholderOnce(url: url, statusCode: httpResponse.statusCode)
                throw ImageLoadError.notFoundOrBlocked
            default:
                let error = HTTPStatusMapper.map(statusCode: httpResponse.statusCode, data: data)
                switch error {
                case .unauthorized, .authenticationFailed, .accessTokenExpired, .refreshTokenExpired:
                    await tokenRefreshCoordinator.invalidateSession()
                default:
                    break
                }
                logger.warning(
                    "Image request returned non-success status. url=\(url.absoluteString) status=\(httpResponse.statusCode) error=\(error.localizedDescription)"
                )
                throw error
            }
        } catch let error as NetworkError {
            throw error
        } catch is ImageLoadError {
            throw NetworkError.transport
        } catch {
            guard !hasLoggedFallback(for: url) else {
                throw NetworkError.transport
            }
            logger.warning("Image transport failed. url=\(url.absoluteString) error=\(error.localizedDescription)")
            throw NetworkError.transport
        }
    }

    private func logFailedURLOnce(url: URL, statusDescription: String) {
        guard !loggedFailedURLs.contains(url) else {
            return
        }
        loggedFailedURLs.insert(url)
        logger.warning("Image unavailable. url=\(url.absoluteString) error=\(statusDescription)")
    }

    private func logFallbackPlaceholderOnce(url: URL, statusCode: Int) {
        let key = fallbackLogKey(url: url, statusCode: statusCode)
        guard loggedFallbackKeys.insert(key).inserted else {
            return
        }
        logger.warning("[ImageLoader] fallbackPlaceholder url=\(url.absoluteString) status=\(statusCode) reason=transport")
    }

    private func hasLoggedFallback(for url: URL) -> Bool {
        loggedFallbackKeys.contains { $0.hasPrefix("\(url.absoluteString)|") }
    }

    private func fallbackLogKey(url: URL, statusCode: Int) -> String {
        "\(url.absoluteString)|\(statusCode)"
    }
}
