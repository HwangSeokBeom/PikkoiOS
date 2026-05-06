import Foundation
import OSLog

enum LogLevel: String, Sendable {
    case debug = "DEBUG"
    case info = "INFO"
    case warning = "WARN"
    case error = "ERROR"
}

struct Logger: Sendable {
    static let shared = Logger(category: "General")

    private let logHandle: OSLog
    private static let isVerboseDebugEnabled = ProcessInfo.processInfo.environment["PIKKO_VERBOSE_LOGS"] == "1"

    init(category: String) {
        logHandle = OSLog(
            subsystem: Bundle.main.bundleIdentifier ?? "com.pikko.ios",
            category: category
        )
    }

    func debug(_ message: String) {
#if DEBUG
        log(message, level: .debug)
#endif
    }

    func debugVerbose(_ message: String) {
#if DEBUG
        guard Self.isVerboseDebugEnabled else { return }
        log(message, level: .debug)
#endif
    }

    func info(_ message: String) {
        log(message, level: .info)
    }

    func warning(_ message: String) {
        log(message, level: .warning)
    }

    func error(_ message: String) {
        log(message, level: .error)
    }

    private func log(_ message: String, level: LogLevel) {
        os_log(
            "%{public}@ %{public}@",
            log: logHandle,
            type: level.osLogType,
            level.rawValue,
            SensitiveLogRedactor.redact(message)
        )
    }
}

#if DEBUG
enum ChatDebugOptions {
    static let isSocketLoggingEnabled = true
    static let isSendLoggingEnabled = true
    static let isMergeLoggingEnabled = true
    static let isComposerGeometryLoggingEnabled = false
    static let isChatListMergeLoggingEnabled = true
}

final class DebugLogDeduplicator: @unchecked Sendable {
    static let shared = DebugLogDeduplicator()

    private var printedKeys = Set<String>()
    private var lastValues = [String: String]()
    private let lock = NSLock()

    private init() {}

    func printOnce(
        key: String,
        level: LogLevel = .debug,
        logger: Logger = .shared,
        message: @autoclosure () -> String
    ) {
        lock.lock()
        let shouldPrint = printedKeys.insert(key).inserted
        lock.unlock()

        guard shouldPrint else { return }
        log(message(), level: level, logger: logger)
    }

    func printWhenChanged(
        key: String,
        value: String,
        level: LogLevel = .debug,
        logger: Logger = .shared,
        message: @autoclosure () -> String
    ) {
        lock.lock()
        let shouldPrint = lastValues[key] != value
        if shouldPrint {
            lastValues[key] = value
        }
        lock.unlock()

        guard shouldPrint else { return }
        log(message(), level: level, logger: logger)
    }

    func reset() {
        lock.lock()
        printedKeys.removeAll()
        lastValues.removeAll()
        lock.unlock()
    }

    private func log(_ message: String, level: LogLevel, logger: Logger) {
        switch level {
        case .debug:
            logger.debug(message)
        case .info:
            logger.info(message)
        case .warning:
            logger.warning(message)
        case .error:
            logger.error(message)
        }
    }
}
#endif

enum SensitiveLogRedactor {
    private static let sensitiveKeys = [
        "access_token",
        "refresh_token",
        "id_token",
        "accessToken",
        "refreshToken",
        "idToken",
        "oauthToken",
        "authorizationCode",
        "authorization_code",
        "deviceToken",
        "device_token",
        "token",
        "Authorization",
        "SeSACKey",
        "SesacKey",
        "PIKKO_SESAC_KEY",
        "RefreshToken",
        "code_verifier",
        "fcmToken",
        "fullToken"
    ]

    static func redact(_ message: String) -> String {
        sensitiveKeys.reduce(message) { partial, key in
            redactValues(for: key, in: partial)
        }
    }

    static func summary(for token: String?) -> String {
        guard let token, !token.isEmpty else {
            return "exists=false"
        }

        return "exists=true length=\(token.count)"
    }

    private static func redactValues(for key: String, in message: String) -> String {
        var redacted = message
        let escapedKey = NSRegularExpression.escapedPattern(for: key)
        let replacements = [
            (
                pattern: "(^|[^A-Za-z0-9_])(\(escapedKey)\\s*[:=]\\s*)([^\\s,;&]+)",
                template: "$1$2<redacted>"
            ),
            (
                pattern: "(\"\(escapedKey)\"\\s*:\\s*\")([^\"]+)(\")",
                template: "$1<redacted>$3"
            )
        ]

        for replacement in replacements {
            guard let regex = try? NSRegularExpression(pattern: replacement.pattern, options: [.caseInsensitive]) else {
                continue
            }

            let range = NSRange(redacted.startIndex..<redacted.endIndex, in: redacted)
            redacted = regex.stringByReplacingMatches(
                in: redacted,
                options: [],
                range: range,
                withTemplate: replacement.template
            )
        }

        return redacted
    }
}

private extension LogLevel {
    var osLogType: OSLogType {
        switch self {
        case .debug:
            return .debug
        case .info:
            return .info
        case .warning:
            return .default
        case .error:
            return .error
        }
    }
}
