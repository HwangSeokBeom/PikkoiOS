import Foundation

struct CheckoutDraft: Equatable, Sendable {
    let storeID: String
    let storeName: String
    let items: [CheckoutDraftLineItem]
    let itemCount: Int
    let subtotalAmount: Decimal
    let subtotalText: String

    var isEmpty: Bool {
        items.isEmpty || itemCount == 0
    }

    var priceValidationRequest: CheckoutPriceValidationRequest {
        CheckoutPriceValidationRequest(
            storeID: storeID,
            items: items.map {
                CheckoutPriceValidationLineItem(
                    menuID: $0.menuID,
                    quantity: $0.quantity,
                    optionSummaryText: $0.optionSummaryText,
                    clientKnownUnitPriceAmount: $0.unitPriceAmount,
                    clientKnownLinePriceAmount: $0.subtotalAmount
                )
            },
            totalPriceAmount: subtotalAmount,
            couponID: nil
        )
    }

    static let empty = CheckoutDraft(
        storeID: "",
        storeName: "",
        items: [],
        itemCount: 0,
        subtotalAmount: .zero,
        subtotalText: "0원"
    )
}

struct CheckoutDraftLineItem: Identifiable, Equatable, Sendable {
    let menuID: String
    let menuName: String
    let imagePath: String?
    let optionSummaryText: String?
    let unitPriceAmount: Decimal
    let unitPriceText: String
    let quantity: Int
    let subtotalAmount: Decimal
    let subtotalText: String

    var id: String { menuID }
}
