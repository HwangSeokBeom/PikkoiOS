import Foundation

enum AppEnvironment: String, Sendable {
    case development
    case staging
    case production

    static var current: AppEnvironment {
        if let rawValue = Bundle.main.object(forInfoDictionaryKey: AppConfiguration.BundleKey.environment) as? String,
           !rawValue.hasPrefix("$("),
           let environment = AppEnvironment(rawValue: rawValue) {
            return environment
        }

#if DEBUG
        return .development
#else
        return .production
#endif
    }
}
