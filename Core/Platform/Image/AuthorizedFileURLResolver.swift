import Foundation

protocol AuthorizedFileURLResolving: Sendable {
    func resolveURL(from path: String) throws -> URL
    func resolveOptionalURL(from path: String?) throws -> URL?
}

struct AuthorizedFileURLResolver: AuthorizedFileURLResolving, Sendable {
    private let configuration: AppConfiguration

    init(configuration: AppConfiguration) {
        self.configuration = configuration
    }

    func resolveURL(from path: String) throws -> URL {
        let trimmedPath = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPath.isEmpty else {
            throw NetworkError.invalidRequest
        }

        if let absoluteURL = URL(string: trimmedPath), absoluteURL.scheme != nil {
            return absoluteURL
        }

        let normalizedPath = normalize(path: trimmedPath)
        guard let resolvedURL = URL(string: normalizedPath, relativeTo: originURL)?.absoluteURL else {
            throw NetworkError.invalidRequest
        }
        return resolvedURL
    }

    func resolveOptionalURL(from path: String?) throws -> URL? {
        guard let path else { return nil }
        return try resolveURL(from: path)
    }

    private var originURL: URL {
        var components = URLComponents()
        components.scheme = configuration.baseURL.scheme
        components.host = configuration.baseURL.host
        components.port = configuration.baseURL.port
        return components.url ?? configuration.baseURL
    }

    private func normalize(path: String) -> String {
        if path.hasPrefix("/v1/") {
            return path
        }

        if path.hasPrefix("/data/") {
            return "/v1\(path)"
        }

        if path.hasPrefix("data/") {
            return "/v1/\(path)"
        }

        if path.hasPrefix("/") {
            return path
        }

        return "/\(path)"
    }
}
