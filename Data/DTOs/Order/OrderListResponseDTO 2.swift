import Foundation

struct OrderListResponseDTO: Decodable, Sendable {
    let data: [OrderWithStatusResponseDTO]
}

struct OrderWithStatusResponseDTO: Decodable, Sendable {
    let orderID: String
    let orderCode: String
    let totalPrice: Decimal
    let review: OrderReviewReferenceDTO?
    let store: StoreSummaryDTOOrder
    let orderMenuList: [OrderMenuQuantityResponseDTO]
    let currentOrderStatus: String
    let orderStatusTimeline: [OrderStatusTimelineResponseDTO]
    let paidAt: String?
    let createdAt: String
    let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case orderID = "order_id"
        case orderCode = "order_code"
        case totalPrice = "total_price"
        case review
        case store
        case orderMenuList = "order_menu_list"
        case currentOrderStatus = "current_order_status"
        case orderStatusTimeline = "order_status_timeline"
        case paidAt
        case createdAt
        case updatedAt
    }
}

struct OrderReviewReferenceDTO: Decodable, Sendable {
    let id: String
    let rating: Decimal
}

struct StoreSummaryDTOOrder: Decodable, Sendable {
    let id: String
    let category: String?
    let name: String
    let close: String?
    let storeImageURLs: [String]

    enum CodingKeys: String, CodingKey {
        case id
        case category
        case name
        case close
        case storeImageURLs = "store_image_urls"
    }
}

struct MenuResponseDTOOrder: Decodable, Sendable {
    let id: String
    let category: String?
    let name: String?
    let detailDescription: String?
    let price: Decimal?
    let tags: [String]
    let menuImageURL: String?

    enum CodingKeys: String, CodingKey {
        case id
        case category
        case name
        case detailDescription = "description"
        case price
        case tags
        case menuImageURL = "menu_image_url"
    }
}

struct OrderMenuQuantityResponseDTO: Decodable, Sendable {
    let menu: MenuResponseDTOOrder
    let quantity: Int
}

struct OrderStatusTimelineResponseDTO: Decodable, Sendable {
    let status: String
    let completed: Bool
    let changedAt: String?
}

