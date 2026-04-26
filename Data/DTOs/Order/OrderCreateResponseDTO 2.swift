import Foundation

struct OrderCreateResponseDTO: Decodable, Sendable {
    let orderID: String
    let orderCode: String
    let totalPrice: Int
    let createdAt: Date
    let updatedAt: Date
    let paymentURL: String?
    let redirectURL: String?
    let paymentToken: String?

    private enum CodingKeys: String, CodingKey {
        case orderID = "order_id"
        case orderCode = "order_code"
        case totalPrice = "total_price"
        case createdAt
        case updatedAt
        case paymentURL = "payment_url"
        case redirectURL = "redirect_url"
        case paymentToken = "payment_token"
    }
}
