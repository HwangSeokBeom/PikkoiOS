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

enum AppConfigurationError: Error, Equatable, Sendable {
    case missingBaseURL
    case invalidBaseURL
    case missingSeSACKey
    case invalidSeSACKey

    var logMessage: String {
        switch self {
        case .missingBaseURL:
            return "PIKKO_BASE_URL is missing. Configure it in Secrets.xcconfig."
        case .invalidBaseURL:
            return "PIKKO_BASE_URL is invalid. Configure a full http/https host in Secrets.xcconfig."
        case .missingSeSACKey:
            return "PIKKO_SESAC_KEY is missing. Configure it in Secrets.xcconfig."
        case .invalidSeSACKey:
            return "PIKKO_SESAC_KEY is invalid. Check the configured value in Secrets.xcconfig."
        }
    }

    var userMessage: String {
#if DEBUG
        switch self {
        case .missingBaseURL:
            return "PIKKO_BASE_URL이 누락되었습니다. Config/Secrets.xcconfig를 확인하세요."
        case .invalidBaseURL:
            return "PIKKO_BASE_URL이 올바르지 않습니다. Config/Secrets.xcconfig를 확인하세요."
        case .missingSeSACKey:
            return "PIKKO_SESAC_KEY가 누락되었습니다. Config/Secrets.xcconfig를 확인하세요."
        case .invalidSeSACKey:
            return "PIKKO_SESAC_KEY가 올바르지 않습니다. Config/Secrets.xcconfig를 확인하세요."
        }
#else
        return "앱 설정을 확인해 주세요."
#endif
    }

    var authUserMessage: String {
#if DEBUG
        userMessage
#else
        "로그인 설정을 확인해 주세요."
#endif
    }
}

struct AppConfiguration: Sendable {
    private static let unresolvedPrefix = "$("
    private static let placeholderBaseURL = "REPLACE_WITH_PIKKO_BASE_URL"
    private static let placeholderSecret = "REPLACE_WITH_SESAC_KEY"
    private static let placeholderKakaoNativeAppKey = "REPLACE_WITH_KAKAO_NATIVE_APP_KEY"
    private static let placeholderGoogleClientID = "REPLACE_WITH_GOOGLE_IOS_CLIENT_ID"
    private static let placeholderGoogleReversedClientID = "REPLACE_WITH_GOOGLE_REVERSED_CLIENT_ID"

    enum BundleKey {
        static let environment = "PIKKO_APP_ENV"
        static let baseURL = "PIKKO_BASE_URL"
        static let baseURLAliases = [baseURL, "PIKKOBaseURL"]
        static let seSACKey = "PIKKO_SESAC_KEY"
        static let seSACKeyAliases = [seSACKey, "PIKKOSeSACKey"]
        static let kakaoNativeAppKey = "KAKAO_NATIVE_APP_KEY"
        static let kakaoNativeAppKeyAliases = [kakaoNativeAppKey, "KakaoNativeAppKey"]
        static let googleIOSClientID = "GOOGLE_IOS_CLIENT_ID"
        static let googleIOSClientIDAliases = [googleIOSClientID, "GoogleIOSClientID", "GIDClientID"]
        static let googleReversedClientID = "GOOGLE_REVERSED_CLIENT_ID"
        static let googleReversedClientIDAliases = [googleReversedClientID, "GoogleReversedClientID"]
        static let internalStubAuthEnabled = "PIKKO_INTERNAL_STUB_AUTH_ENABLED"
    }

    let environment: AppEnvironment
    let baseURL: URL?
    let baseURLError: AppConfigurationError?
    let seSACKey: String
    let seSACKeyError: AppConfigurationError?
    let hasValidSeSACKey: Bool
    let kakaoNativeAppKey: String?
    let googleIOSClientID: String?
    let googleReversedClientID: String?
    let isInternalStubAuthEnabled: Bool
    let authorizationHeaderFormat: TokenHeaderFormat

    let defaultTimeout: TimeInterval
    let uploadTimeout: TimeInterval
    let paymentValidationTimeout: TimeInterval

    init(
        environment: AppEnvironment = .current,
        bundle: Bundle = .main,
        baseURL: URL? = nil,
        seSACKey: String? = nil,
        kakaoNativeAppKey: String? = nil,
        googleIOSClientID: String? = nil,
        googleReversedClientID: String? = nil,
        internalStubAuthEnabled: Bool? = nil,
        authorizationHeaderFormat: TokenHeaderFormat = .raw
    ) {
        let resolvedBaseURL = Self.resolveBaseURL(explicitBaseURL: baseURL, bundle: bundle)
        let resolvedSeSACKey = Self.resolveSeSACKey(explicitSeSACKey: seSACKey, bundle: bundle)
        let resolvedGoogleIOSClientID = googleIOSClientID ?? Self.resolveGoogleIOSClientID(bundle: bundle)
        self.environment = environment
        self.authorizationHeaderFormat = authorizationHeaderFormat
        self.baseURL = resolvedBaseURL.url
        self.baseURLError = resolvedBaseURL.error
        self.seSACKey = resolvedSeSACKey.value
        self.seSACKeyError = resolvedSeSACKey.error
        self.hasValidSeSACKey = resolvedSeSACKey.error == nil
        self.kakaoNativeAppKey = kakaoNativeAppKey ?? Self.resolveKakaoNativeAppKey(bundle: bundle)
        self.googleIOSClientID = resolvedGoogleIOSClientID
        self.googleReversedClientID = googleReversedClientID
            ?? Self.resolveGoogleReversedClientID(
                bundle: bundle,
                googleIOSClientID: resolvedGoogleIOSClientID
            )
        self.isInternalStubAuthEnabled = internalStubAuthEnabled ?? Self.resolveInternalStubAuthEnabled(bundle: bundle)
        self.defaultTimeout = URLSessionConfigurationFactory.defaultRequestTimeout
        self.uploadTimeout = URLSessionConfigurationFactory.uploadRequestTimeout
        self.paymentValidationTimeout = URLSessionConfigurationFactory.paymentValidationRequestTimeout
    }

    private static func resolveBaseURL(
        explicitBaseURL: URL?,
        bundle: Bundle
    ) -> (url: URL?, error: AppConfigurationError?) {
        let rawValue: String?
        let shouldLog: Bool

        if let explicitBaseURL {
            rawValue = explicitBaseURL.absoluteString
            shouldLog = false
        } else {
            rawValue = configuredRawString(forAnyOf: BundleKey.baseURLAliases, bundle: bundle)
            shouldLog = true
        }

        let error = baseURLValidationError(for: rawValue)
        if shouldLog, let error {
            AppConfigurationWarningLogger.shared.logOnce(
                key: BundleKey.baseURL,
                message: error.logMessage
            )
        }

        return (normalizedBaseURL(from: rawValue), error)
    }

    private static func resolveSeSACKey(
        explicitSeSACKey: String?,
        bundle: Bundle
    ) -> (value: String, error: AppConfigurationError?) {
        let rawValue: String?
        let shouldLog: Bool

        if let explicitSeSACKey {
            rawValue = explicitSeSACKey
            shouldLog = false
        } else {
            rawValue = configuredRawString(forAnyOf: BundleKey.seSACKeyAliases, bundle: bundle)
            shouldLog = true
        }

        let error = seSACKeyValidationError(for: rawValue)
        if shouldLog, let error {
            AppConfigurationWarningLogger.shared.logOnce(
                key: BundleKey.seSACKey,
                message: error.logMessage
            )
        }

        return (rawValue ?? placeholderSecret, error)
    }

    private static func resolveKakaoNativeAppKey(bundle: Bundle) -> String? {
        configuredString(
            forAnyOf: BundleKey.kakaoNativeAppKeyAliases,
            bundle: bundle,
            placeholder: placeholderKakaoNativeAppKey
        )
    }

    private static func resolveGoogleIOSClientID(bundle: Bundle) -> String? {
        configuredString(
            forAnyOf: BundleKey.googleIOSClientIDAliases,
            bundle: bundle,
            placeholder: placeholderGoogleClientID
        )
    }

    private static func resolveGoogleReversedClientID(
        bundle: Bundle,
        googleIOSClientID: String?
    ) -> String? {
        if let configuredReversedClientID = configuredString(
            forAnyOf: BundleKey.googleReversedClientIDAliases,
            bundle: bundle,
            placeholder: placeholderGoogleReversedClientID
        ) {
            return configuredReversedClientID
        }

        return googleIOSClientID.flatMap(reversedGoogleClientID(from:))
    }

    private static func resolveInternalStubAuthEnabled(bundle: Bundle) -> Bool {
        guard let rawValue = configuredRawString(
            forAnyOf: [BundleKey.internalStubAuthEnabled],
            bundle: bundle
        ) else {
            return false
        }

        switch rawValue.lowercased() {
        case "1", "true", "yes", "y":
            return true
        default:
            return false
        }
    }

    static func baseURLValidationError(for rawValue: String?) -> AppConfigurationError? {
        guard let normalizedValue = normalizedConfiguredValue(rawValue) else {
            return .missingBaseURL
        }

        guard !isPlaceholderValue(normalizedValue, placeholder: placeholderBaseURL),
              !isUnresolvedBuildSettingReference(normalizedValue) else {
            return .invalidBaseURL
        }

        guard let url = URL(string: normalizedValue),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = url.host,
              !host.isEmpty,
              host.caseInsensitiveCompare("v1") != .orderedSame else {
            return .invalidBaseURL
        }

        return nil
    }

    static func normalizedBaseURL(from rawValue: String?) -> URL? {
        guard baseURLValidationError(for: rawValue) == nil,
              let normalizedValue = normalizedConfiguredValue(rawValue),
              var components = URLComponents(string: normalizedValue) else {
            return nil
        }

        components.query = nil
        components.fragment = nil
        return components.url
    }

    static func seSACKeyValidationError(for rawValue: String?) -> AppConfigurationError? {
        guard let normalizedValue = normalizedConfiguredValue(rawValue) else {
            return .missingSeSACKey
        }

        guard !isPlaceholderValue(normalizedValue, placeholder: placeholderSecret),
              !isUnresolvedBuildSettingReference(normalizedValue) else {
            return .invalidSeSACKey
        }

        return isValidSeSACKey(normalizedValue) ? nil : .invalidSeSACKey
    }

    private static func configuredString(
        forAnyOf keys: [String],
        bundle: Bundle,
        placeholder: String? = nil
    ) -> String? {
        guard let rawValue = configuredRawString(forAnyOf: keys, bundle: bundle),
              let trimmed = normalizedConfiguredValue(rawValue),
              !isPlaceholderValue(trimmed, placeholder: placeholder),
              !isUnresolvedBuildSettingReference(trimmed) else {
            return nil
        }
        return trimmed
    }

    private static func configuredRawString(forAnyOf keys: [String], bundle: Bundle) -> String? {
        for key in keys {
            if let environmentValue = ProcessInfo.processInfo.environment[key] {
                let trimmedEnvironmentValue = environmentValue.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmedEnvironmentValue.isEmpty {
                    return trimmedEnvironmentValue
                }
            }
        }

        for key in keys {
            guard let rawValue = bundle.object(forInfoDictionaryKey: key) as? String else {
                continue
            }

            let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return trimmed
            }
        }

        return nil
    }

    static func isValidSeSACKey(_ key: String) -> Bool {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty &&
            !isPlaceholderValue(trimmed, placeholder: placeholderSecret) &&
            !isUnresolvedBuildSettingReference(trimmed)
    }

    static func normalizedConfiguredValue(_ rawValue: String?) -> String? {
        guard let rawValue else { return nil }
        var trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)

        if (trimmed.hasPrefix("\"") && trimmed.hasSuffix("\"")) ||
            (trimmed.hasPrefix("'") && trimmed.hasSuffix("'")) {
            trimmed = String(trimmed.dropFirst().dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        guard !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    private static func isUnresolvedBuildSettingReference(_ value: String) -> Bool {
        value.hasPrefix(unresolvedPrefix) && value.hasSuffix(")")
    }

    private static func isPlaceholderValue(_ value: String, placeholder: String?) -> Bool {
        if let placeholder, value == placeholder {
            return true
        }

        return value.hasPrefix("<") && value.hasSuffix(">")
    }

    var hasValidBaseURL: Bool {
        baseURL != nil && baseURLError == nil
    }

    var networkConfigurationError: AppConfigurationError? {
        baseURLError ?? seSACKeyError
    }

    var remoteAuthDisabledReason: String? {
        networkConfigurationError?.userMessage
    }

    var hasValidKakaoNativeAppKey: Bool {
        kakaoNativeAppKey != nil
    }

    var hasValidGoogleSignInConfiguration: Bool {
        googleIOSClientID != nil && googleReversedClientID != nil
    }

    var canAttemptRemoteAuth: Bool {
        hasValidBaseURL && hasValidSeSACKey
    }

    static func reversedGoogleClientID(from clientID: String) -> String? {
        let trimmed = clientID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              trimmed != placeholderGoogleClientID,
              !trimmed.hasPrefix(unresolvedPrefix) else {
            return nil
        }

        let components = trimmed.split(separator: ".").map(String.init)
        guard components.count >= 2 else {
            return nil
        }

        return components.reversed().joined(separator: ".")
    }
}

final class AppConfigurationWarningLogger: @unchecked Sendable {
    static let shared = AppConfigurationWarningLogger()

    private let lock = NSLock()
    private var emittedKeys = Set<String>()

    private init() {}

    func logOnce(key: String, message: String) {
        lock.lock()
        let shouldLog = emittedKeys.insert(key).inserted
        lock.unlock()

        guard shouldLog else { return }
        Logger.shared.warning(message)
    }
}
