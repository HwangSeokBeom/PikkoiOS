import Foundation

struct CheckoutPriceValidationRequestDTO: Encodable, Sendable {
    let storeID: String
    let orderMenuList: [CheckoutPriceValidationLineItemDTO]
    let totalPrice: Int
    let couponID: String?

    private enum CodingKeys: String, CodingKey {
        case storeID = "store_id"
        case orderMenuList = "order_menu_list"
        case totalPrice = "total_price"
        case couponID = "coupon_id"
    }
}

struct CheckoutPriceValidationLineItemDTO: Encodable, Sendable {
    let menuID: String
    let quantity: Int
    let optionSummaryText: String?
    let clientKnownUnitPrice: Int
    let clientKnownLinePrice: Int

    private enum CodingKeys: String, CodingKey {
        case menuID = "menu_id"
        case quantity
        case optionSummaryText = "option_summary_text"
        case clientKnownUnitPrice = "client_known_unit_price"
        case clientKnownLinePrice = "client_known_line_price"
    }
}

struct CheckoutPriceValidationResponseDTO: Sendable {
    let validatedTotalPrice: Int?
    let issues: [CheckoutPriceValidationIssueDTO]
    let message: String?
}

struct CheckoutPriceValidationIssueDTO: Sendable {
    let menuID: String?
    let kind: String
    let message: String
}
