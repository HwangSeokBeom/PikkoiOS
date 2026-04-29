import Foundation

struct PaymentValidationRequest: Equatable, Sendable {
    let orderID: String?
    let orderCode: String?
    let merchantUID: String?
    let impUID: String
    let success: Bool?
    let errorMessage: String?
}
