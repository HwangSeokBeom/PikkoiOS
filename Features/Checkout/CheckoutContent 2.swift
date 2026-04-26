import Foundation

enum CheckoutFeatureError: Error, Equatable {
    case validation(message: String)
    case validationIssues([CheckoutPriceValidationIssue])
    case authenticationRequired
    case configurationRequired
    case businessAuthorization(message: String)
    case notFound(message: String)
    case unavailable(message: String)
}
