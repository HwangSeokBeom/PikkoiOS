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

    init(category: String) {
        logHandle = OSLog(
            subsystem: Bundle.main.bundleIdentifier ?? "com.pikko.ios",
            category: category
        )
    }

    func debug(_ message: String) {
        log(message, level: .debug)
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
        "Authorization",
        "RefreshToken",
        "code_verifier"
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

        return "exists=true prefix=\(String(token.prefix(4)))... length=\(token.count)"
    }

    private static func redactValues(for key: String, in message: String) -> String {
        var redacted = message
        let escapedKey = NSRegularExpression.escapedPattern(for: key)
        let replacements = [
            (
                pattern: "(\(escapedKey)\\s*[:=]\\s*)([^\\s,;&]+)",
                template: "$1<redacted>"
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
