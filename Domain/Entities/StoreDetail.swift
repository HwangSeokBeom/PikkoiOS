import Foundation

struct StoreDetail: Equatable, Sendable {
    let id: String
    let category: String?
    let name: String
    let description: String?
    let hashTags: [String]
    let openTime: String?
    let closeTime: String?
    let address: String?
    let estimatedPickupMinutes: Int?
    let parkingGuide: String?
    let imagePaths: [String]
    let isPicchelin: Bool
    var isLiked: Bool
    var likeCount: Int
    let totalReviewCount: Int
    let totalOrderCount: Int
    let totalRating: Double?
    let owner: StoreOwner?
    let longitude: Double?
    let latitude: Double?
    let menus: [StoreMenu]
    let createdAt: Date?
    let updatedAt: Date?
}

struct StoreOwner: Equatable, Sendable {
    let id: String
    let nick: String
    let profileImagePath: String?
}

struct StoreMenu: Equatable, Sendable {
    let id: String
    let storeID: String
    let category: String?
    let name: String
    let description: String?
    let originInformation: String?
    let price: Decimal
    let isSoldOut: Bool
    let tags: [String]
    let imagePath: String?
    let createdAt: Date?
    let updatedAt: Date?
}
