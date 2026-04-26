import Foundation

struct CreatedOrder: Equatable, Sendable {
    let id: String
    let orderCode: String
    let totalPriceAmount: Decimal
    let createdAt: Date
    let updatedAt: Date
    let paymentBridgePayload: CheckoutPaymentBridgePayload?
}

struct ValidatedPaymentReceipt: Equatable, Sendable {
    let paymentID: String?
    let orderID: String?
    let orderCode: String?
    let totalPriceAmount: Decimal?
    let createdAt: Date?
    let updatedAt: Date?
}
