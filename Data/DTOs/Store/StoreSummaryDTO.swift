import Foundation

struct GeolocationDTO: Decodable, Sendable {
    let longitude: Double?
    let latitude: Double?
}

struct StoreSummaryDTO: Decodable, Sendable {
    let storeID: String
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
    let distance: Double?

    private enum CodingKeys: String, CodingKey {
        case storeID = "store_id"
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
        case distance
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
        self.name = try container.decode(String.self, forKey: .name)
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
        self.distance = try container.decodeIfPresent(Double.self, forKey: .distance)
    }
}
