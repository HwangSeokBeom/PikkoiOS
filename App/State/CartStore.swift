import Foundation

enum CartStoreDecision: Equatable, Sendable {
    case available
    case replaceRequired(currentStoreID: String, requestedStoreID: String)
}

struct CartLineItem: Identifiable, Equatable, Sendable {
    let menuID: String
    let storeID: String
    let storeName: String
    let menuName: String
    let imagePath: String?
    let optionSummaryText: String?
    let unitPrice: Decimal
    var quantity: Int

    var id: String { menuID }

    var subtotal: Decimal {
        unitPrice * Decimal(quantity)
    }
}

@MainActor
final class CartStore: ObservableObject {
    @Published private(set) var summary: CartSummary = .empty
    @Published private(set) var currentStoreID: String?
    @Published private(set) var currentStoreName: String?
    @Published private(set) var items: [CartLineItem] = []

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

    func replaceCart(for storeID: String, storeName: String? = nil) {
        currentStoreID = storeID
        currentStoreName = storeName
        items = []
        summary = .empty
    }

    func apply(summary: CartSummary, for storeID: String?) {
        self.summary = summary

        if summary.itemCount == 0 {
            currentStoreID = nil
            currentStoreName = nil
            items = []
        } else if let storeID {
            currentStoreID = storeID
        }
    }

    func quantity(for menuID: String, in storeID: String) -> Int {
        guard currentStoreID == storeID else {
            return 0
        }

        return items.first(where: { $0.menuID == menuID })?.quantity ?? 0
    }

    func setQuantity(
        _ quantity: Int,
        menuID: String,
        menuName: String,
        unitPrice: Decimal,
        imagePath: String?,
        optionSummaryText: String? = nil,
        storeID: String,
        storeName: String
    ) {
        if case .replaceRequired = decisionForUsingCart(with: storeID) {
            replaceCart(for: storeID, storeName: storeName)
        } else {
            bind(to: storeID)
        }

        currentStoreName = storeName

        guard quantity > 0 else {
            items.removeAll { $0.menuID == menuID }
            recalculateSummary()
            return
        }

        if let index = items.firstIndex(where: { $0.menuID == menuID }) {
            items[index].quantity = quantity
        } else {
            items.append(
                CartLineItem(
                    menuID: menuID,
                storeID: storeID,
                storeName: storeName,
                menuName: menuName,
                imagePath: imagePath,
                optionSummaryText: optionSummaryText,
                unitPrice: unitPrice,
                quantity: quantity
            )
            )
        }

        recalculateSummary()
    }

    func clear() {
        currentStoreID = nil
        currentStoreName = nil
        items = []
        summary = .empty
    }

    func makeCheckoutDraft() -> CheckoutDraft? {
        guard let currentStoreID, !items.isEmpty else {
            return nil
        }

        let subtotalAmount = items.reduce(Decimal.zero) { $0 + $1.subtotal }
        let itemCount = items.reduce(0) { $0 + $1.quantity }
        let storeName = currentStoreName ?? items.first?.storeName ?? ""

        let lineItems = items.map { item in
            CheckoutDraftLineItem(
                menuID: item.menuID,
                menuName: item.menuName,
                imagePath: item.imagePath,
                optionSummaryText: item.optionSummaryText,
                unitPriceAmount: item.unitPrice,
                unitPriceText: formatWon(item.unitPrice),
                quantity: item.quantity,
                subtotalAmount: item.subtotal,
                subtotalText: formatWon(item.subtotal)
            )
        }

        return CheckoutDraft(
            storeID: currentStoreID,
            storeName: storeName,
            items: lineItems,
            itemCount: itemCount,
            subtotalAmount: subtotalAmount,
            subtotalText: formatWon(subtotalAmount)
        )
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

    private func recalculateSummary() {
        let itemCount = items.reduce(0) { $0 + $1.quantity }
        let subtotal = items.reduce(Decimal.zero) { $0 + $1.subtotal }

        summary = CartSummary(
            itemCount: itemCount,
            subtotalText: formatWon(subtotal)
        )

        if itemCount == 0 {
            currentStoreID = nil
            currentStoreName = nil
        }
    }

    private func formatWon(_ amount: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale(identifier: "ko_KR")
        return "\(formatter.string(from: amount as NSDecimalNumber) ?? "\(amount)")원"
    }
}
