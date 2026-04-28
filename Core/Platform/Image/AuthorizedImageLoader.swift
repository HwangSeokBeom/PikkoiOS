import Foundation

protocol AuthorizedImageLoading: Sendable {
    func imageData(for path: String) async throws -> Data
    func cachedImageData(for path: String) async throws -> Data?
    func removeCachedImage(for path: String) async throws
}

actor AuthorizedImageLoader: AuthorizedImageLoading {
    private let logger = Logger(category: "AuthorizedImageLoader")
    private let session: URLSession
    private let requestBuilder: RequestBuilder
    private let tokenRefreshCoordinator: TokenRefreshCoordinator
    private let fileURLResolver: any AuthorizedFileURLResolving
    private let imageCache: ImageCache

    private var inFlightTasks: [URL: Task<Data, Error>] = [:]

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
            logger.warning("Image load failed. url=\(url.absoluteString) error=\(error.localizedDescription)")
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
            default:
                let error = HTTPStatusMapper.map(statusCode: httpResponse.statusCode, data: data)
                switch error {
                case .unauthorized, .authenticationFailed, .accessTokenExpired, .refreshTokenExpired, .forbidden:
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
        } catch {
            logger.warning("Image transport failed. url=\(url.absoluteString) error=\(error.localizedDescription)")
            throw NetworkError.transport
        }
    }
}
