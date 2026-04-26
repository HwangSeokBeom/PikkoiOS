import Foundation

struct CheckoutPriceValidationResult: Equatable, Sendable {
    let validatedTotalPriceAmount: Decimal?
    let issues: [CheckoutPriceValidationIssue]
    let message: String?

    var isValid: Bool {
        issues.isEmpty
    }

    static let valid = CheckoutPriceValidationResult(
        validatedTotalPriceAmount: nil,
        issues: [],
        message: nil
    )
}

struct CheckoutPriceValidationIssue: Identifiable, Equatable, Sendable {
    enum Kind: String, Equatable, Sendable {
        case priceChanged
        case soldOut
        case menuUnavailable
        case storeClosed
        case invalidCoupon
        case unknown
    }

    let id: String
    let menuID: String?
    let kind: Kind
    let message: String

    var isBlocking: Bool {
        true
    }
}

struct CheckoutPaymentBridgePayload: Equatable, Sendable {
    let paymentURL: URL?
    let redirectURL: URL?
    let paymentToken: String?
}
