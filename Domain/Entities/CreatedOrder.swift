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

struct PaymentReceipt: Equatable, Sendable {
    let impUID: String?
    let merchantUID: String
    let amount: Decimal
    let currency: String?
    let status: String
    let methodText: String?
    let paidAt: Date?
    let receiptURL: URL?

    var isPaymentCompleted: Bool {
        status.lowercased() == "paid" && paidAt != nil
    }
}
