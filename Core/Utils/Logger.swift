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
            message
        )
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
