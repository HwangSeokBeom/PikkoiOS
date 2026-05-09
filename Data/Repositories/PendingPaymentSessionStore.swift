import Foundation

actor PendingPaymentSessionStore {
    static let shared = PendingPaymentSessionStore(store: UserDefaultsStore())

    private let store: any UserDefaultsStoring
    private let storageKey = "pending_payment_sessions"

    init(store: any UserDefaultsStoring) {
        self.store = store
    }

    func recoverableSession(userID: String, storeID: String, totalPriceAmount: Decimal) -> PendingPaymentSession? {
        sessions(userID: userID)
            .filter { $0.state.isRecoverable }
            .filter { $0.storeID == storeID && $0.totalPriceAmount == totalPriceAmount }
            .sorted { $0.lastUpdatedAt > $1.lastUpdatedAt }
            .first
    }

    func session(orderCode: String, userID: String) -> PendingPaymentSession? {
        sessions(userID: userID).first { $0.orderCode == orderCode }
    }

    func upsert(_ session: PendingPaymentSession) {
        var nextSessions = allSessions()
        nextSessions.removeAll { $0.userID == session.userID && $0.orderCode == session.orderCode }
        nextSessions.insert(session, at: 0)
        persist(nextSessions)
    }

    func update(
        orderCode: String,
        userID: String,
        state: PaymentFlowState,
        impUID: String? = nil,
        now: Date = Date()
    ) {
        var nextSessions = allSessions()
        guard let index = nextSessions.firstIndex(where: { $0.userID == userID && $0.orderCode == orderCode }) else {
            return
        }
        nextSessions[index].state = state
        if let impUID {
            nextSessions[index].impUID = impUID
        }
        nextSessions[index].lastUpdatedAt = now
        persist(nextSessions)
    }

    func remove(orderCode: String, userID: String) {
        var nextSessions = allSessions()
        let previousCount = nextSessions.count
        nextSessions.removeAll { $0.userID == userID && $0.orderCode == orderCode }
        guard nextSessions.count != previousCount else { return }
        persist(nextSessions)
    }

    func clearAll() {
        store.removeValue(forKey: storageKey)
    }

    private func sessions(userID: String) -> [PendingPaymentSession] {
        allSessions().filter { $0.userID == userID }
    }

    private func allSessions() -> [PendingPaymentSession] {
        store.codableValue([PendingPaymentSession].self, forKey: storageKey) ?? []
    }

    private func persist(_ sessions: [PendingPaymentSession]) {
        do {
            try store.setCodable(Array(sessions.prefix(20)), forKey: storageKey)
        } catch {
            Logger.shared.warning("[PaymentSession] persistFailed message=\(error.localizedDescription)")
        }
    }
}
