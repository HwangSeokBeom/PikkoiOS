import Foundation

struct OrderCreateRequestDTO: Encodable, Sendable {
    let storeID: String
    let orderMenuList: [OrderCreateMenuItemDTO]
    let totalPrice: Int

    init(submission: CheckoutOrderSubmission) {
        self.storeID = submission.storeID
        self.orderMenuList = submission.items.map {
            OrderCreateMenuItemDTO(menuID: $0.menuID, quantity: $0.quantity)
        }
        self.totalPrice = NSDecimalNumber(decimal: submission.totalPriceAmount).intValue
        // TODO: Map pickup memo, coupon, address, and payment provider once the backend
        // exposes those fields on OrderCreateRequestDTO.
    }

    private enum CodingKeys: String, CodingKey {
        case storeID = "store_id"
        case orderMenuList = "order_menu_list"
        case totalPrice = "total_price"
    }
}

struct OrderCreateMenuItemDTO: Encodable, Sendable {
    let menuID: String
    let quantity: Int

    private enum CodingKeys: String, CodingKey {
        case menuID = "menu_id"
        case quantity
    }
}
