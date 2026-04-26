import Foundation

actor FallbackAuthorizedImageLoader: AuthorizedImageLoading {
    private let primaryLoader: any AuthorizedImageLoading
    private var generatedStorage: [String: Data] = [:]

    init(primaryLoader: any AuthorizedImageLoading) {
        self.primaryLoader = primaryLoader
    }

    func imageData(for path: String) async throws -> Data {
        guard let normalizedPath = normalizedSeed(from: path) else {
            return try await primaryLoader.imageData(for: path)
        }

        if let cached = generatedStorage[normalizedPath] {
            return cached
        }

        let data = PlaceholderImageFactory.makeData(seed: normalizedPath)
        generatedStorage[normalizedPath] = data
        return data
    }

    func cachedImageData(for path: String) async throws -> Data? {
        guard let normalizedPath = normalizedSeed(from: path) else {
            return try await primaryLoader.cachedImageData(for: path)
        }

        return generatedStorage[normalizedPath]
    }

    func removeCachedImage(for path: String) async throws {
        guard let normalizedPath = normalizedSeed(from: path) else {
            try await primaryLoader.removeCachedImage(for: path)
            return
        }

        generatedStorage[normalizedPath] = nil
    }

    private func normalizedSeed(from path: String) -> String? {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        if let url = URL(string: trimmed), url.scheme != nil {
            return nil
        }

        if trimmed.hasPrefix("/v1/") || trimmed.hasPrefix("/data/") || trimmed.hasPrefix("data/") || trimmed.hasPrefix("/") {
            return nil
        }

        return trimmed
    }
}
