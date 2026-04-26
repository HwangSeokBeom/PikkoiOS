import Foundation

struct CheckoutPriceValidationRequest: Equatable, Sendable {
    let storeID: String
    let items: [CheckoutPriceValidationLineItem]
    let totalPriceAmount: Decimal
    let couponID: String?

    var isEmpty: Bool {
        items.isEmpty
    }
}

struct CheckoutPriceValidationLineItem: Identifiable, Equatable, Sendable {
    let menuID: String
    let quantity: Int
    let optionSummaryText: String?
    let clientKnownUnitPriceAmount: Decimal
    let clientKnownLinePriceAmount: Decimal

    var id: String { menuID }
}
