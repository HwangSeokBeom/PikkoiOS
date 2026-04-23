import Foundation

enum TokenHeaderFormat: Sendable {
    case raw
    case bearer

    func format(_ token: String) -> String {
        switch self {
        case .raw:
            return token
        case .bearer:
            return "Bearer \(token)"
        }
    }
}

struct AppConfiguration: Sendable {
    private static let unresolvedPrefix = "$("
    private static let placeholderSecret = "REPLACE_WITH_SESAC_KEY"

    enum BundleKey {
        static let environment = "PIKKO_APP_ENV"
        static let baseURL = "PIKKO_BASE_URL"
        static let seSACKey = "PIKKO_SESAC_KEY"
    }

    let environment: AppEnvironment
    let baseURL: URL
    let seSACKey: String
    let authorizationHeaderFormat: TokenHeaderFormat

    let defaultTimeout: TimeInterval
    let uploadTimeout: TimeInterval
    let paymentValidationTimeout: TimeInterval

    init(
        environment: AppEnvironment = .current,
        bundle: Bundle = .main,
        baseURL: URL? = nil,
        seSACKey: String? = nil,
        authorizationHeaderFormat: TokenHeaderFormat = .raw
    ) {
        self.environment = environment
        self.authorizationHeaderFormat = authorizationHeaderFormat
        self.baseURL = baseURL ?? Self.resolveBaseURL(bundle: bundle, environment: environment)
        self.seSACKey = seSACKey ?? Self.resolveSeSACKey(bundle: bundle)
        self.defaultTimeout = URLSessionConfigurationFactory.defaultRequestTimeout
        self.uploadTimeout = URLSessionConfigurationFactory.uploadRequestTimeout
        self.paymentValidationTimeout = URLSessionConfigurationFactory.paymentValidationRequestTimeout
    }

    private static func resolveBaseURL(bundle: Bundle, environment: AppEnvironment) -> URL {
        if let configuredValue = configuredString(for: BundleKey.baseURL, bundle: bundle),
           let configuredURL = URL(string: configuredValue) {
            return configuredURL
        }

        Logger.shared.warning("PIKKO_BASE_URL is missing or invalid. Falling back to default host.")

        switch environment {
        case .development, .staging, .production:
            return URL(string: "http://pickup.sesac.kr:42678")!
        }
    }

    private static func resolveSeSACKey(bundle: Bundle) -> String {
        if let configuredValue = configuredString(for: BundleKey.seSACKey, bundle: bundle),
           configuredValue != placeholderSecret {
            return configuredValue
        }

        Logger.shared.warning("PIKKO_SESAC_KEY is not configured. Home API calls can fail with status 420.")
        return placeholderSecret
    }

    private static func configuredString(for key: String, bundle: Bundle) -> String? {
        guard let rawValue = bundle.object(forInfoDictionaryKey: key) as? String else {
            return nil
        }

        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              !trimmed.hasPrefix(unresolvedPrefix) else {
            return nil
        }

        return trimmed
    }
}
