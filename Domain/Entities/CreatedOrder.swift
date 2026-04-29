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

enum PaymentReceiptCacheState: Equatable, Sendable {
    case verified(receipt: PaymentReceipt?)
    case unavailable

    var logValue: String {
        switch self {
        case .verified:
            return "verified"
        case .unavailable:
            return "unavailable"
        }
    }
}

actor PaymentReceiptCache {
    static let shared = PaymentReceiptCache()

    private struct Entry: Sendable {
        let state: PaymentReceiptCacheState
        let expiresAt: Date?
    }

    private let unavailableTTL: TimeInterval
    private let store: any UserDefaultsStoring
    private let storageKey: String
    private var entries: [String: Entry] = [:]

    init(
        unavailableTTL: TimeInterval = 120,
        store: any UserDefaultsStoring = UserDefaultsStore(),
        storageKey: String = "payment.receiptCache"
    ) {
        self.unavailableTTL = unavailableTTL
        self.store = store
        self.storageKey = storageKey
        self.entries = store
            .codableValue([StoredPaymentReceiptCacheEntry].self, forKey: storageKey)?
            .reduce(into: [String: Entry]()) { partial, storedEntry in
                partial[storedEntry.orderCode] = Entry(
                    state: storedEntry.state,
                    expiresAt: storedEntry.expiresAt
                )
            } ?? [:]
    }

    func state(for orderCode: String, now: Date = Date()) -> PaymentReceiptCacheState? {
        guard let entry = entries[orderCode] else {
            return nil
        }
        if let expiresAt = entry.expiresAt, expiresAt <= now {
            entries[orderCode] = nil
            persist()
            return nil
        }
        return entry.state
    }

    func markVerified(orderCode: String, receipt: PaymentReceipt? = nil) {
        entries[orderCode] = Entry(state: .verified(receipt: receipt), expiresAt: nil)
        persist()
    }

    func markUnavailable(orderCode: String, now: Date = Date()) {
        entries[orderCode] = Entry(
            state: .unavailable,
            expiresAt: now.addingTimeInterval(unavailableTTL)
        )
        persist()
    }

    func clear() {
        entries = [:]
        store.removeValue(forKey: storageKey)
    }

    private func persist() {
        do {
            try store.setCodable(
                entries.map { orderCode, entry in
                    StoredPaymentReceiptCacheEntry(
                        orderCode: orderCode,
                        state: entry.state,
                        expiresAt: entry.expiresAt
                    )
                },
                forKey: storageKey
            )
        } catch {
            Logger.shared.warning("Failed to persist payment receipt cache: \(error.localizedDescription)")
        }
    }
}

private struct StoredPaymentReceiptCacheEntry: Codable {
    let orderCode: String
    let stateRawValue: String
    let expiresAt: Date?

    init(orderCode: String, state: PaymentReceiptCacheState, expiresAt: Date?) {
        self.orderCode = orderCode
        self.expiresAt = expiresAt
        switch state {
        case .verified:
            stateRawValue = "verified"
        case .unavailable:
            stateRawValue = "unavailable"
        }
    }

    var state: PaymentReceiptCacheState {
        switch stateRawValue {
        case "verified":
            return .verified(receipt: nil)
        case "unavailable":
            return .unavailable
        default:
            return .unavailable
        }
    }
}
