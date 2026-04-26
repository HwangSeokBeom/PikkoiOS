import Foundation

struct UserInfoResponseDTO: Decodable, Sendable {
    let userID: String
    let nick: String
    let profileImage: String?

    private enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case id
        case nick
        case profileImage
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        if let userID = try container.decodeIfPresent(String.self, forKey: .userID) {
            self.userID = userID
        } else if let fallbackID = try container.decodeIfPresent(String.self, forKey: .id) {
            self.userID = fallbackID
        } else {
            throw DecodingError.keyNotFound(
                CodingKeys.userID,
                DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Missing user identifier")
            )
        }

        self.nick = try container.decode(String.self, forKey: .nick)
        self.profileImage = try container.decodeIfPresent(String.self, forKey: .profileImage)
    }
}

struct MenuResponseDTO: Decodable, Sendable {
    let menuID: String
    let storeID: String
    let category: String?
    let name: String
    let description: String?
    let originInformation: String?
    let price: Decimal
    let isSoldOut: Bool
    let tags: [String]
    let menuImageURL: String?
    let createdAt: String?
    let updatedAt: String?

    private enum CodingKeys: String, CodingKey {
        case menuID = "menu_id"
        case id
        case storeID = "store_id"
        case category
        case name
        case description
        case originInformation = "origin_information"
        case price
        case isSoldOut = "is_sold_out"
        case tags
        case menuImageURL = "menu_image_url"
        case createdAt
        case updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        if let menuID = try container.decodeIfPresent(String.self, forKey: .menuID) {
            self.menuID = menuID
        } else if let fallbackID = try container.decodeIfPresent(String.self, forKey: .id) {
            self.menuID = fallbackID
        } else {
            throw DecodingError.keyNotFound(
                CodingKeys.menuID,
                DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Missing menu identifier")
            )
        }

        self.storeID = try container.decodeIfPresent(String.self, forKey: .storeID) ?? ""
        self.category = try container.decodeIfPresent(String.self, forKey: .category)
        self.name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        self.description = try container.decodeIfPresent(String.self, forKey: .description)
        self.originInformation = try container.decodeIfPresent(String.self, forKey: .originInformation)
        self.price = try container.decodeIfPresent(Decimal.self, forKey: .price) ?? .zero
        self.isSoldOut = try container.decodeIfPresent(Bool.self, forKey: .isSoldOut) ?? false
        self.tags = try container.decodeIfPresent([String].self, forKey: .tags) ?? []
        self.menuImageURL = try container.decodeIfPresent(String.self, forKey: .menuImageURL)
        self.createdAt = try container.decodeIfPresent(String.self, forKey: .createdAt)
        self.updatedAt = try container.decodeIfPresent(String.self, forKey: .updatedAt)
    }
}

struct StoreDetailResponseDTO: Decodable, Sendable {
    let storeID: String
    let category: String?
    let name: String
    let description: String?
    let hashTags: [String]
    let open: String?
    let close: String?
    let address: String?
    let estimatedPickupTime: Int?
    let parkingGuide: String?
    let storeImageURLs: [String]
    let isPicchelin: Bool
    let isPick: Bool
    let pickCount: Int
    let totalReviewCount: Int
    let totalOrderCount: Int
    let totalRating: Double?
    let creator: UserInfoResponseDTO?
    let geolocation: GeolocationDTO?
    let menuList: [MenuResponseDTO]
    let createdAt: String?
    let updatedAt: String?

    private enum CodingKeys: String, CodingKey {
        case storeID = "store_id"
        case id
        case category
        case name
        case description
        case hashTags
        case open
        case close
        case address
        case estimatedPickupTime = "estimated_pickup_time"
        case parkingGuide = "parking_guide"
        case storeImageURLs = "store_image_urls"
        case isPicchelin = "is_picchelin"
        case isPick = "is_pick"
        case pickCount = "pick_count"
        case totalReviewCount = "total_review_count"
        case totalOrderCount = "total_order_count"
        case totalRating = "total_rating"
        case creator
        case geolocation
        case menuList = "menu_list"
        case createdAt
        case updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        if let storeID = try container.decodeIfPresent(String.self, forKey: .storeID) {
            self.storeID = storeID
        } else if let fallbackID = try container.decodeIfPresent(String.self, forKey: .id) {
            self.storeID = fallbackID
        } else {
            throw DecodingError.keyNotFound(
                CodingKeys.storeID,
                DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Missing store identifier")
            )
        }

        self.category = try container.decodeIfPresent(String.self, forKey: .category)
        self.name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        self.description = try container.decodeIfPresent(String.self, forKey: .description)
        self.hashTags = try container.decodeIfPresent([String].self, forKey: .hashTags) ?? []
        self.open = try container.decodeIfPresent(String.self, forKey: .open)
        self.close = try container.decodeIfPresent(String.self, forKey: .close)
        self.address = try container.decodeIfPresent(String.self, forKey: .address)
        self.estimatedPickupTime = try container.decodeIfPresent(Int.self, forKey: .estimatedPickupTime)
        self.parkingGuide = try container.decodeIfPresent(String.self, forKey: .parkingGuide)
        self.storeImageURLs = try container.decodeIfPresent([String].self, forKey: .storeImageURLs) ?? []
        self.isPicchelin = try container.decodeIfPresent(Bool.self, forKey: .isPicchelin) ?? false
        self.isPick = try container.decodeIfPresent(Bool.self, forKey: .isPick) ?? false
        self.pickCount = try container.decodeIfPresent(Int.self, forKey: .pickCount) ?? 0
        self.totalReviewCount = try container.decodeIfPresent(Int.self, forKey: .totalReviewCount) ?? 0
        self.totalOrderCount = try container.decodeIfPresent(Int.self, forKey: .totalOrderCount) ?? 0
        self.totalRating = try container.decodeIfPresent(Double.self, forKey: .totalRating)
        self.creator = try container.decodeIfPresent(UserInfoResponseDTO.self, forKey: .creator)
        self.geolocation = try container.decodeIfPresent(GeolocationDTO.self, forKey: .geolocation)
        self.menuList = try container.decodeIfPresent([MenuResponseDTO].self, forKey: .menuList) ?? []
        self.createdAt = try container.decodeIfPresent(String.self, forKey: .createdAt)
        self.updatedAt = try container.decodeIfPresent(String.self, forKey: .updatedAt)
    }
}
