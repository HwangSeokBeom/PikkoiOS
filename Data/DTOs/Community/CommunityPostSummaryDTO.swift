import Foundation

struct CommunityPostSummaryResponseDTO: Decodable, Sendable {
    let postID: String
    let category: String?
    let title: String
    let content: String
    let store: CommunityStoreSummaryDTO?
    let geolocation: GeolocationDTO?
    let creator: CommunityUserInfoResponseDTO
    let files: [String]
    let isLike: Bool
    let likeCount: Double
    let createdAt: String?
    let updatedAt: String?

    private enum CodingKeys: String, CodingKey {
        case postID = "post_id"
        case category
        case title
        case content
        case store
        case geolocation
        case creator
        case files
        case isLike = "is_like"
        case likeCount = "like_count"
        case createdAt
        case updatedAt
    }
}

struct CommunityUserInfoResponseDTO: Decodable, Sendable {
    let userID: String
    let nick: String
    let profileImage: String?

    private enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case nick
        case profileImage
    }
}

struct CommunityStoreSummaryDTO: Decodable, Sendable {
    let id: String
    let category: String?
    let name: String
    let close: String?
    let storeImageURLs: [String]
    let isPicchelin: Bool
    let isPick: Bool
    let pickCount: Int
    let hashTags: [String]
    let totalRating: Double?
    let totalOrderCount: Int
    let totalReviewCount: Int
    let geolocation: GeolocationDTO?

    private enum CodingKeys: String, CodingKey {
        case id
        case category
        case name
        case close
        case storeImageURLs = "store_image_urls"
        case isPicchelin = "is_picchelin"
        case isPick = "is_pick"
        case pickCount = "pick_count"
        case hashTags
        case totalRating = "total_rating"
        case totalOrderCount = "total_order_count"
        case totalReviewCount = "total_review_count"
        case geolocation
    }
}
