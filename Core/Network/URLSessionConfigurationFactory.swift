import Foundation

enum URLSessionConfigurationFactory {
    static let defaultRequestTimeout: TimeInterval = 15
    static let uploadRequestTimeout: TimeInterval = 60
    static let paymentValidationRequestTimeout: TimeInterval = 30

    static func makeDefaultConfiguration() -> URLSessionConfiguration {
        makeConfiguration(timeout: defaultRequestTimeout)
    }

    static func makeUploadConfiguration() -> URLSessionConfiguration {
        makeConfiguration(timeout: uploadRequestTimeout)
    }

    static func makePaymentValidationConfiguration() -> URLSessionConfiguration {
        makeConfiguration(timeout: paymentValidationRequestTimeout)
    }

    private static func makeConfiguration(timeout: TimeInterval) -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.default
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = timeout
        configuration.waitsForConnectivity = false
        return configuration
    }
}
