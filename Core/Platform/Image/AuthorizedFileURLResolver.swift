import Foundation

protocol AuthorizedFileURLResolving: Sendable {
    func resolveURL(from path: String) throws -> URL
    func resolveOptionalURL(from path: String?) throws -> URL?
}

struct AuthorizedFileURLResolver: AuthorizedFileURLResolving, Sendable {
    private let configuration: AppConfiguration
    private let urlBuilder = URLBuilder()

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

        guard let baseURL = configuration.baseURL else {
            throw NetworkError.configuration(configuration.baseURLError ?? .missingBaseURL)
        }

        return try urlBuilder.makeURL(
            baseURL: try urlBuilder.makeOriginURL(baseURL: baseURL),
            path: normalize(path: trimmedPath)
        )
    }

    func resolveOptionalURL(from path: String?) throws -> URL? {
        guard let path else { return nil }
        return try resolveURL(from: path)
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
