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
    case atsBlocked
    case missingSeSACKey
    case invalidSeSACKey

    var logMessage: String {
        switch self {
        case .missingBaseURL:
            return "PIKKO_BASE_URL is missing. Configure it in Secrets.xcconfig."
        case .invalidBaseURL:
            return "PIKKO_BASE_URL is invalid. Configure a full http/https host in Secrets.xcconfig."
        case .atsBlocked:
            return "ATS blocked insecure HTTP request. Check scoped ATS exception or use HTTPS."
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
            return "PIKKO_BASE_URL이 누락되었습니다. Config/AuthSecrets.xcconfig 또는 Config/LocalSecrets.xcconfig를 확인하세요."
        case .invalidBaseURL:
            return "PIKKO_BASE_URL이 올바르지 않습니다. Config/AuthSecrets.xcconfig 또는 Config/LocalSecrets.xcconfig를 확인하세요."
        case .atsBlocked:
            return "네트워크 설정을 확인해 주세요."
        case .missingSeSACKey:
            return "PIKKO_SESAC_KEY가 누락되었습니다. Config/AuthSecrets.xcconfig 또는 Config/LocalSecrets.xcconfig를 확인하세요."
        case .invalidSeSACKey:
            return "PIKKO_SESAC_KEY가 올바르지 않습니다. Config/AuthSecrets.xcconfig 또는 Config/LocalSecrets.xcconfig를 확인하세요."
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
    private static let placeholderPortOneUserCode = "REPLACE_WITH_PORTONE_USER_CODE"
    private static let placeholderPortOnePgID = "REPLACE_WITH_PORTONE_PG_ID"
    private static let knownPlaceholderValues: Set<String> = [
        "placeholder",
        "your_portone_user_code",
        "portone_user_code",
        "$(portone_user_code)",
        "imp00000000",
        "replace_me",
        "replace_with_portone_user_code",
        "missing_or_placeholder"
    ]

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
        static let chatSocketDebugEnabled = "PIKKO_CHAT_SOCKET_DEBUG_ENABLED"
        static let portOneUserCode = "PORTONE_USER_CODE"
        static let portOnePg = "PORTONE_PG"
        static let portOnePgID = "PORTONE_PG_ID"
        static let portOnePayMethod = "PORTONE_PAY_METHOD"
        static let portOneAppScheme = "PORTONE_APP_SCHEME"
        static let paymentTestMode = "PAYMENT_TEST_MODE"
    }

    struct ConfiguredValueDiagnostic: Equatable, Sendable {
        let key: String
        let source: String
        let state: String
        let rawMasked: String

        var logStatus: String {
            "\(state):source=\(source):rawMasked=\(rawMasked)"
        }
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
    let isChatSocketDebugEnabled: Bool
    let portOneUserCode: String?
    let portOnePg: String
    let portOnePgID: String?
    let portOnePayMethod: String
    let portOneAppScheme: String
    let portOneUserCodeDiagnostic: ConfiguredValueDiagnostic
    let portOnePgDiagnostic: ConfiguredValueDiagnostic
    let portOnePgIDDiagnostic: ConfiguredValueDiagnostic
    let portOnePayMethodDiagnostic: ConfiguredValueDiagnostic
    let portOneAppSchemeDiagnostic: ConfiguredValueDiagnostic
    let isPaymentTestMode: Bool
    let authorizationHeaderFormat: TokenHeaderFormat
    let isHLSManifestRewriteFallbackEnabled: Bool

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
        chatSocketDebugEnabled: Bool? = nil,
        portOneUserCode: String? = nil,
        portOnePg: String? = nil,
        portOnePgID: String? = nil,
        portOnePayMethod: String? = nil,
        portOneAppScheme: String? = nil,
        paymentTestMode: Bool? = nil,
        authorizationHeaderFormat: TokenHeaderFormat = .raw,
        hlsManifestRewriteFallbackEnabled: Bool? = nil
    ) {
        let resolvedBaseURL = Self.resolveBaseURL(explicitBaseURL: baseURL, bundle: bundle)
        let resolvedSeSACKey = Self.resolveSeSACKey(explicitSeSACKey: seSACKey, bundle: bundle)
        let resolvedGoogleIOSClientID = googleIOSClientID ?? Self.resolveGoogleIOSClientID(bundle: bundle)
        let resolvedPortOneUserCode = Self.resolveConfiguredValue(
            explicitValue: portOneUserCode,
            key: BundleKey.portOneUserCode,
            bundle: bundle,
            placeholder: Self.placeholderPortOneUserCode
        )
        let resolvedPortOnePg = Self.resolveConfiguredValue(
            explicitValue: portOnePg,
            key: BundleKey.portOnePg,
            bundle: bundle,
            defaultValue: "html5_inicis"
        )
        let resolvedPortOnePgID = Self.resolveOptionalConfiguredValue(
            explicitValue: portOnePgID,
            key: BundleKey.portOnePgID,
            bundle: bundle,
            placeholder: Self.placeholderPortOnePgID
        )
        let resolvedPortOnePayMethod = Self.resolveConfiguredValue(
            explicitValue: portOnePayMethod,
            key: BundleKey.portOnePayMethod,
            bundle: bundle,
            defaultValue: "card"
        )
        let resolvedPortOneAppScheme = Self.resolveConfiguredValue(
            explicitValue: portOneAppScheme,
            key: BundleKey.portOneAppScheme,
            bundle: bundle,
            defaultValue: "pikko"
        )
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
        self.isChatSocketDebugEnabled = chatSocketDebugEnabled ?? Self.resolveChatSocketDebugEnabled(bundle: bundle)
        self.portOneUserCode = resolvedPortOneUserCode.value
        self.portOnePg = resolvedPortOnePg.value ?? "html5_inicis"
        self.portOnePgID = resolvedPortOnePgID.value
        self.portOnePayMethod = resolvedPortOnePayMethod.value ?? "card"
        self.portOneAppScheme = resolvedPortOneAppScheme.value ?? "pikko"
        self.portOneUserCodeDiagnostic = resolvedPortOneUserCode.diagnostic
        self.portOnePgDiagnostic = resolvedPortOnePg.diagnostic
        self.portOnePgIDDiagnostic = resolvedPortOnePgID.diagnostic
        self.portOnePayMethodDiagnostic = resolvedPortOnePayMethod.diagnostic
        self.portOneAppSchemeDiagnostic = resolvedPortOneAppScheme.diagnostic
        self.isPaymentTestMode = paymentTestMode ?? Self.resolvePaymentTestMode(bundle: bundle)
        self.defaultTimeout = URLSessionConfigurationFactory.defaultRequestTimeout
        self.uploadTimeout = URLSessionConfigurationFactory.uploadRequestTimeout
        self.paymentValidationTimeout = URLSessionConfigurationFactory.paymentValidationRequestTimeout
        _ = hlsManifestRewriteFallbackEnabled
        self.isHLSManifestRewriteFallbackEnabled = false

        if environment == .production,
           Self.isPotentiallyUnsafePaymentConfiguration(
            isPaymentTestMode: self.isPaymentTestMode,
            pgID: self.portOnePgID
           ) {
            AppConfigurationWarningLogger.shared.logOnce(
                key: "PORTONE_PRODUCTION_TEST_CONFIGURATION",
                message: "Production payment configuration points at a test PG. Real payment is blocked until PORTONE_PG_ID/PAYMENT_TEST_MODE are corrected."
            )
        }
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
        configuredBool(for: BundleKey.internalStubAuthEnabled, bundle: bundle)
    }

    private static func resolveChatSocketDebugEnabled(bundle: Bundle) -> Bool {
        configuredBool(for: BundleKey.chatSocketDebugEnabled, bundle: bundle)
    }

    private static func resolvePaymentTestMode(bundle: Bundle) -> Bool {
        configuredBool(for: BundleKey.paymentTestMode, bundle: bundle)
    }

    private static func configuredBool(for key: String, bundle: Bundle) -> Bool {
        guard let rawValue = configuredRawString(
            forAnyOf: [key],
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
        configuredRawStringWithSource(forAnyOf: keys, bundle: bundle)?.value
    }

    private static func resolveConfiguredValue(
        explicitValue: String?,
        key: String,
        bundle: Bundle,
        defaultValue: String? = nil,
        placeholder: String? = nil
    ) -> (value: String?, diagnostic: ConfiguredValueDiagnostic) {
        let rawValue: String?
        let source: String

        if let explicitValue {
            rawValue = explicitValue
            source = "AppConfiguration.explicit.\(key)"
        } else if let configured = configuredRawStringWithSource(forAnyOf: [key], bundle: bundle) {
            rawValue = configured.value
            source = configured.source
        } else if let defaultValue {
            rawValue = defaultValue
            source = "default.\(key)"
        } else {
            rawValue = nil
            source = "missing:expected_xcconfig=Config/Secrets.xcconfig"
        }

        let diagnostic = configuredValueDiagnostic(
            key: key,
            rawValue: rawValue,
            source: source,
            placeholder: placeholder
        )

        guard diagnostic.state == "valid",
              let normalizedValue = normalizedConfiguredValue(rawValue) else {
            return (nil, diagnostic)
        }

        return (normalizedValue, diagnostic)
    }

    private static func resolveOptionalConfiguredValue(
        explicitValue: String?,
        key: String,
        bundle: Bundle,
        placeholder: String? = nil
    ) -> (value: String?, diagnostic: ConfiguredValueDiagnostic) {
        let rawValue: String?
        let source: String

        if let explicitValue {
            rawValue = explicitValue
            source = "AppConfiguration.explicit.\(key)"
        } else if let configured = configuredRawStringWithSource(
            forAnyOf: [key],
            bundle: bundle,
            allowEmpty: true
        ) {
            rawValue = configured.value
            source = configured.source
        } else {
            rawValue = nil
            source = "missing:optional_xcconfig=Config/Secrets.xcconfig"
        }

        let diagnostic = optionalConfiguredValueDiagnostic(
            key: key,
            rawValue: rawValue,
            source: source,
            placeholder: placeholder
        )

        guard diagnostic.state == "valid",
              let normalizedValue = normalizedConfiguredValue(rawValue) else {
            return (nil, diagnostic)
        }

        return (normalizedValue, diagnostic)
    }

    private static func configuredRawStringWithSource(
        forAnyOf keys: [String],
        bundle: Bundle,
        allowEmpty: Bool = false
    ) -> (value: String, source: String)? {
        for key in keys {
            if let environmentValue = ProcessInfo.processInfo.environment[key] {
                let trimmedEnvironmentValue = environmentValue.trimmingCharacters(in: .whitespacesAndNewlines)
                if allowEmpty || !trimmedEnvironmentValue.isEmpty {
                    return (trimmedEnvironmentValue, "ProcessInfo.environment.\(key)")
                }
            }
        }

        for key in keys {
            guard let rawValue = bundle.object(forInfoDictionaryKey: key) as? String else {
                continue
            }

            let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if allowEmpty || !trimmed.isEmpty {
                return (trimmed, "Info.plist.\(key)")
            }
        }

        return nil
    }

    static func portOneUserCodeDiagnostic(bundle: Bundle = .main) -> ConfiguredValueDiagnostic {
        configuredValueDiagnostic(
            key: BundleKey.portOneUserCode,
            bundle: bundle,
            placeholder: placeholderPortOneUserCode
        )
    }

    static func configuredValueDiagnostic(
        key: String,
        bundle: Bundle = .main,
        placeholder: String? = nil
    ) -> ConfiguredValueDiagnostic {
        guard let raw = configuredRawStringWithSource(forAnyOf: [key], bundle: bundle) else {
            return ConfiguredValueDiagnostic(
                key: key,
                source: "missing:expected_xcconfig=Config/Secrets.xcconfig|Config/AuthSecrets.xcconfig|Config/LocalSecrets.xcconfig",
                state: "missing",
                rawMasked: "-"
            )
        }

        return configuredValueDiagnostic(
            key: key,
            rawValue: raw.value,
            source: raw.source,
            placeholder: placeholder
        )
    }

    private static func configuredValueDiagnostic(
        key: String,
        rawValue: String?,
        source: String,
        placeholder: String? = nil
    ) -> ConfiguredValueDiagnostic {
        guard let rawValue else {
            return ConfiguredValueDiagnostic(key: key, source: source, state: "missing", rawMasked: "-")
        }

        guard let normalized = normalizedConfiguredValue(rawValue) else {
            return ConfiguredValueDiagnostic(key: key, source: source, state: "empty", rawMasked: "-")
        }

        if isPlaceholderValue(normalized, placeholder: placeholder) {
            return ConfiguredValueDiagnostic(key: key, source: source, state: "placeholder", rawMasked: maskedConfiguredValue(normalized))
        }

        if isUnresolvedBuildSettingReference(normalized) {
            return ConfiguredValueDiagnostic(key: key, source: source, state: "placeholder", rawMasked: maskedConfiguredValue(normalized))
        }

        if key == BundleKey.portOneUserCode,
           !isValidPortOneUserCode(normalized) {
            return ConfiguredValueDiagnostic(key: key, source: source, state: "invalid", rawMasked: maskedConfiguredValue(normalized))
        }

        return ConfiguredValueDiagnostic(key: key, source: source, state: "valid", rawMasked: maskedConfiguredValue(normalized))
    }

    private static func optionalConfiguredValueDiagnostic(
        key: String,
        rawValue: String?,
        source: String,
        placeholder: String? = nil
    ) -> ConfiguredValueDiagnostic {
        let diagnostic = configuredValueDiagnostic(
            key: key,
            rawValue: rawValue,
            source: source,
            placeholder: placeholder
        )

        switch diagnostic.state {
        case "missing", "empty":
            return ConfiguredValueDiagnostic(
                key: key,
                source: diagnostic.source,
                state: "emptyOptional",
                rawMasked: diagnostic.rawMasked
            )
        case "placeholder":
            return ConfiguredValueDiagnostic(
                key: key,
                source: diagnostic.source,
                state: "placeholderOptional",
                rawMasked: diagnostic.rawMasked
            )
        default:
            return diagnostic
        }
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

        let normalizedLowercasedValue = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return knownPlaceholderValues.contains(normalizedLowercasedValue)
            || value.hasPrefix("<") && value.hasSuffix(">")
            || value.hasPrefix("REPLACE_WITH_")
    }

    private static func isValidPortOneUserCode(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("imp") else {
            return false
        }

        let containsWhitespace = trimmed.rangeOfCharacter(from: .whitespacesAndNewlines) != nil
        return trimmed.count >= 8 && !containsWhitespace
    }

    private static func maskedConfiguredValue(_ value: String) -> String {
        let normalizedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalizedValue.hasPrefix("imp"), normalizedValue.count > 3 {
            let suffix = normalizedValue.suffix(min(4, normalizedValue.count - 3))
            return "imp…\(suffix)"
        }

        guard normalizedValue.count > 6 else {
            return normalizedValue.isEmpty ? "-" : "***"
        }

        let prefix = normalizedValue.prefix(4)
        let suffix = normalizedValue.suffix(2)
        return "\(prefix)…\(suffix)"
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

    var shouldShowPaymentWarning: Bool {
        isPaymentTestMode || Self.isPotentiallyUnsafePaymentConfiguration(
            isPaymentTestMode: false,
            pgID: portOnePgID
        )
    }

    var portOnePgId: String? {
        portOnePgID
    }

    var blocksProductionPayment: Bool {
        environment == .production && Self.isPotentiallyUnsafePaymentConfiguration(
            isPaymentTestMode: isPaymentTestMode,
            pgID: portOnePgID
        )
    }

    private static func isPotentiallyUnsafePaymentConfiguration(
        isPaymentTestMode: Bool,
        pgID: String?
    ) -> Bool {
        if isPaymentTestMode {
            return true
        }

        guard let normalizedPGID = normalizedConfiguredValue(pgID) else {
            return false
        }
        return normalizedPGID.range(of: "test", options: [.caseInsensitive]) != nil
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
