import Foundation

enum CartStoreDecision: Equatable, Sendable {
    case available
    case replaceRequired(currentStoreID: String, requestedStoreID: String)
}

@MainActor
final class CartStore: ObservableObject {
    @Published private(set) var summary: CartSummary = .empty
    @Published private(set) var currentStoreID: String?

    private let cartRepository: CartRepository

    init(cartRepository: CartRepository) {
        self.cartRepository = cartRepository
    }

    var hasActiveCart: Bool {
        currentStoreID != nil && summary.itemCount > 0
    }

    func decisionForUsingCart(with storeID: String) -> CartStoreDecision {
        guard let currentStoreID else {
            return .available
        }

        if currentStoreID == storeID || summary.itemCount == 0 {
            return .available
        }

        return .replaceRequired(currentStoreID: currentStoreID, requestedStoreID: storeID)
    }

    func bind(to storeID: String) {
        if summary.itemCount == 0 || currentStoreID == nil {
            currentStoreID = storeID
        }
    }

    func replaceCart(for storeID: String) {
        currentStoreID = storeID
        summary = .empty
    }

    func apply(summary: CartSummary, for storeID: String?) {
        self.summary = summary

        if summary.itemCount == 0 {
            currentStoreID = nil
        } else if let storeID {
            currentStoreID = storeID
        }
    }

    func clear() {
        currentStoreID = nil
        summary = .empty
    }

    func refresh(for session: UserSession?) async {
        guard session != nil else {
            clear()
            return
        }

        do {
            let fetchedSummary = try await cartRepository.fetchCartSummary(for: session)
            apply(summary: fetchedSummary, for: currentStoreID)
        } catch {
            clear()
            Logger.shared.warning("Cart refresh failed: \(error.localizedDescription)")
        }
    }
}
