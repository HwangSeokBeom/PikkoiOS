import Foundation

enum PaymentFlowState: String, Codable, Equatable, Sendable {
    case idle
    case creatingOrder
    case orderCreated
    case openingPayment
    case paymentInProgress
    case paymentReturned
    case validatingReceipt
    case validationSucceeded
    case validationFailed
    case paymentCancelled
    case recoverablePending
    case completed

    var isRecoverable: Bool {
        switch self {
        case .orderCreated,
             .openingPayment,
             .paymentInProgress,
             .paymentReturned,
             .validatingReceipt,
             .validationFailed,
             .paymentCancelled,
             .recoverablePending:
            return true
        case .idle, .creatingOrder, .validationSucceeded, .completed:
            return false
        }
    }
}

struct PendingPaymentSession: Codable, Equatable, Identifiable, Sendable {
    var id: String { orderCode }

    let userID: String
    let orderCode: String
    let orderID: String?
    let storeID: String
    let storeName: String
    let menuSummary: String
    let totalPriceAmount: Decimal
    let createdAt: Date
    var state: PaymentFlowState
    var impUID: String?
    var lastUpdatedAt: Date

    var hasReturnedReceipt: Bool {
        impUID?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }
}

extension PendingPaymentSession {
    static let staleSessionTTL: TimeInterval = 60 * 60 * 24 * 3

    func isStale(now: Date = Date()) -> Bool {
        lastUpdatedAt.addingTimeInterval(Self.staleSessionTTL) <= now
    }
}
