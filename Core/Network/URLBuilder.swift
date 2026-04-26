import Foundation

struct URLBuilder: Sendable {
    func makeURL(
        baseURL: URL,
        path: String,
        query: [URLQueryItem] = []
    ) throws -> URL {
        let trimmedPath = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPath.isEmpty else {
            throw NetworkError.invalidRequest
        }

        let normalizedBaseURL = try normalizedBaseURL(from: baseURL)
        let baseURLWithPath: URL

        if let absoluteURL = absoluteURL(from: trimmedPath) {
            baseURLWithPath = absoluteURL
        } else {
            guard var components = URLComponents(
                url: normalizedBaseURL,
                resolvingAgainstBaseURL: false
            ) else {
                throw NetworkError.invalidRequest
            }

            components.query = nil
            components.fragment = nil
            components.path = mergedPath(
                basePath: components.path,
                relativePath: trimmedPath
            )

            guard let assembledURL = components.url else {
                throw NetworkError.invalidRequest
            }

            baseURLWithPath = assembledURL
        }

        guard var components = URLComponents(
            url: baseURLWithPath,
            resolvingAgainstBaseURL: false
        ) else {
            throw NetworkError.invalidRequest
        }

        if !query.isEmpty {
            components.queryItems = query
        }

        guard let url = components.url else {
            throw NetworkError.invalidRequest
        }

        return try validatedAssembledURL(url)
    }

    func makeOriginURL(baseURL: URL) throws -> URL {
        guard var components = URLComponents(
            url: try normalizedBaseURL(from: baseURL),
            resolvingAgainstBaseURL: false
        ) else {
            throw NetworkError.invalidRequest
        }

        components.path = ""
        components.query = nil
        components.fragment = nil

        guard let url = components.url else {
            throw NetworkError.invalidRequest
        }

        return try validatedAssembledURL(url)
    }

    private func normalizedBaseURL(from candidate: URL) throws -> URL {
        let rawValue = candidate.absoluteString
        if let error = AppConfiguration.baseURLValidationError(for: rawValue) {
            throw NetworkError.configuration(error)
        }

        guard let normalizedBaseURL = AppConfiguration.normalizedBaseURL(from: rawValue) else {
            throw NetworkError.configuration(.invalidBaseURL)
        }

        return normalizedBaseURL
    }

    private func absoluteURL(from path: String) -> URL? {
        guard let candidate = URL(string: path),
              let scheme = candidate.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return nil
        }

        return candidate
    }

    private func mergedPath(basePath: String, relativePath: String) -> String {
        let baseSegments = basePath.split(separator: "/").map(String.init)
        let relativeSegments = relativePath.split(separator: "/").map(String.init)
        let pathSegments = baseSegments + relativeSegments

        if pathSegments.isEmpty {
            return "/"
        }

        return "/" + pathSegments.joined(separator: "/")
    }

    private func validatedAssembledURL(_ url: URL) throws -> URL {
        guard let host = url.host,
              host.caseInsensitiveCompare("v1") != .orderedSame else {
            assertionFailure("Invalid URL assembled: \(url.absoluteString)")
            throw NetworkError.invalidRequest
        }

        return url
    }
}
