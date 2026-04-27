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

    init(userID: String, nick: String, profileImage: String?) {
        self.userID = userID
        self.nick = nick
        self.profileImage = profileImage
    }

    private enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case id
        case nick
        case profileImage
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.userID = try container.decodeIfPresent(String.self, forKey: .userID)
            ?? container.decodeIfPresent(String.self, forKey: .id)
            ?? "unknown-user"
        self.nick = try container.decodeIfPresent(String.self, forKey: .nick) ?? "픽코 사용자"
        self.profileImage = try container.decodeIfPresent(String.self, forKey: .profileImage)
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

    init(
        id: String,
        category: String?,
        name: String,
        close: String?,
        storeImageURLs: [String],
        isPicchelin: Bool,
        isPick: Bool,
        pickCount: Int,
        hashTags: [String],
        totalRating: Double?,
        totalOrderCount: Int,
        totalReviewCount: Int,
        geolocation: GeolocationDTO?
    ) {
        self.id = id
        self.category = category
        self.name = name
        self.close = close
        self.storeImageURLs = storeImageURLs
        self.isPicchelin = isPicchelin
        self.isPick = isPick
        self.pickCount = pickCount
        self.hashTags = hashTags
        self.totalRating = totalRating
        self.totalOrderCount = totalOrderCount
        self.totalReviewCount = totalReviewCount
        self.geolocation = geolocation
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case storeID = "store_id"
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

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decodeIfPresent(String.self, forKey: .id)
            ?? container.decodeIfPresent(String.self, forKey: .storeID)
            ?? ""
        self.category = try container.decodeIfPresent(String.self, forKey: .category)
        self.name = try container.decodeIfPresent(String.self, forKey: .name) ?? "가게 정보"
        self.close = try container.decodeIfPresent(String.self, forKey: .close)
        self.storeImageURLs = try container.decodeIfPresent([String].self, forKey: .storeImageURLs) ?? []
        self.isPicchelin = try container.decodeIfPresent(Bool.self, forKey: .isPicchelin) ?? false
        self.isPick = try container.decodeIfPresent(Bool.self, forKey: .isPick) ?? false
        self.pickCount = try container.decodeIfPresent(Int.self, forKey: .pickCount) ?? 0
        self.hashTags = try container.decodeIfPresent([String].self, forKey: .hashTags) ?? []
        self.totalRating = try container.decodeIfPresent(Double.self, forKey: .totalRating)
        self.totalOrderCount = try container.decodeIfPresent(Int.self, forKey: .totalOrderCount) ?? 0
        self.totalReviewCount = try container.decodeIfPresent(Int.self, forKey: .totalReviewCount) ?? 0
        self.geolocation = try container.decodeIfPresent(GeolocationDTO.self, forKey: .geolocation)
    }
}
