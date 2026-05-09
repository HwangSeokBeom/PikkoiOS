import Foundation

actor HiddenOrderHistoryStore {
    static let shared = HiddenOrderHistoryStore(store: UserDefaultsStore())

    private let store: any UserDefaultsStoring

    init(store: any UserDefaultsStoring) {
        self.store = store
    }

    func isHidden(orderCode: String, userID: String) -> Bool {
        hiddenCodes(userID: userID).contains(orderCode)
    }

    func hide(order: OrderSummary, userID: String) {
        guard order.status.isTerminal else {
            Logger.shared.warning("[HiddenOrderHistory] hideBlocked orderCode=\(order.orderCode) reason=nonTerminal")
            return
        }
        var codes = hiddenCodes(userID: userID)
        codes.insert(order.orderCode)
        persist(codes, userID: userID)
        Logger.shared.debug("[HiddenOrderHistory] hide orderCode=\(order.orderCode)")
    }

    func unhide(orderCode: String, userID: String) {
        var codes = hiddenCodes(userID: userID)
        codes.remove(orderCode)
        persist(codes, userID: userID)
        Logger.shared.debug("[HiddenOrderHistory] unhide orderCode=\(orderCode)")
    }

    func reset(userID: String) {
        store.removeValue(forKey: storageKey(userID: userID))
    }

    func apply(to orders: [OrderSummary], userID: String) -> [OrderSummary] {
        let hidden = hiddenCodes(userID: userID)
        return orders.filter { order in
            guard hidden.contains(order.orderCode) else { return true }
            if order.status.isTerminal {
                return false
            }
            Logger.shared.debug("[HiddenOrderHistory] ignoredHiddenActiveOrder orderCode=\(order.orderCode)")
            return true
        }
    }

    private func hiddenCodes(userID: String) -> Set<String> {
        Set(store.codableValue([String].self, forKey: storageKey(userID: userID)) ?? [])
    }

    private func persist(_ codes: Set<String>, userID: String) {
        do {
            try store.setCodable(Array(codes).sorted(), forKey: storageKey(userID: userID))
        } catch {
            Logger.shared.warning("[HiddenOrderHistory] persistFailed message=\(error.localizedDescription)")
        }
    }

    private func storageKey(userID: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let suffix = userID
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .unicodeScalars
            .map { allowed.contains($0) ? Character($0) : "_" }
        let normalized = String(suffix)
        return "hidden_order_history_codes_\(normalized.isEmpty ? "unknown" : normalized)"
    }
}
