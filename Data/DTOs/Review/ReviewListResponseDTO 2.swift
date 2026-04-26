import Foundation

struct ReviewResponseDTO: Decodable, Sendable {
    let reviewID: String
    let content: String
    let rating: Int
    let reviewImageURLs: [String]
    let orderMenuList: [String]
    let creator: UserInfoResponseDTO
    let userTotalReviewCount: Int
    let userTotalRating: Double?
    let createdAt: String?
    let updatedAt: String?

    private enum CodingKeys: String, CodingKey {
        case reviewID = "review_id"
        case id
        case content
        case rating
        case reviewImageURLs = "review_image_urls"
        case orderMenuList = "order_menu_list"
        case creator
        case userTotalReviewCount = "user_total_review_count"
        case userTotalRating = "user_total_rating"
        case createdAt
        case updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        if let reviewID = try container.decodeIfPresent(String.self, forKey: .reviewID) {
            self.reviewID = reviewID
        } else if let fallbackID = try container.decodeIfPresent(String.self, forKey: .id) {
            self.reviewID = fallbackID
        } else {
            throw DecodingError.keyNotFound(
                CodingKeys.reviewID,
                DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Missing review identifier")
            )
        }

        self.content = try container.decodeIfPresent(String.self, forKey: .content) ?? ""
        self.rating = container.decodeLossyIntIfPresent(forKey: .rating) ?? 0
        self.reviewImageURLs = try container.decodeIfPresent([String].self, forKey: .reviewImageURLs) ?? []
        self.orderMenuList = try container.decodeIfPresent([String].self, forKey: .orderMenuList) ?? []
        self.creator = try container.decode(UserInfoResponseDTO.self, forKey: .creator)
        self.userTotalReviewCount = try container.decodeIfPresent(Int.self, forKey: .userTotalReviewCount) ?? 0
        self.userTotalRating = try container.decodeIfPresent(Double.self, forKey: .userTotalRating)
        self.createdAt = try container.decodeIfPresent(String.self, forKey: .createdAt)
        self.updatedAt = try container.decodeIfPresent(String.self, forKey: .updatedAt)
    }
}

struct ReviewImageResponseDTO: Decodable, Sendable {
    let reviewImageURLs: [String]

    private enum CodingKeys: String, CodingKey {
        case reviewImageURLs = "review_image_urls"
    }
}

struct ReviewCreateRequestDTO: Encodable, Sendable {
    let content: String
    let rating: Int
    let reviewImageURLs: [String]?
    let orderCode: String

    private enum CodingKeys: String, CodingKey {
        case content
        case rating
        case reviewImageURLs = "review_image_urls"
        case orderCode = "order_code"
    }
}

struct ReviewUpdateRequestDTO: Encodable, Sendable {
    let content: String
    let rating: Int
    let reviewImageURLs: [String]?

    private enum CodingKeys: String, CodingKey {
        case content
        case rating
        case reviewImageURLs = "review_image_urls"
    }
}

struct ReviewListResponseDTO: Decodable, Sendable {
    let data: [ReviewResponseDTO]
    let nextCursor: String?

    private enum CodingKeys: String, CodingKey {
        case data
        case nextCursor = "next_cursor"
    }
}

struct ReviewRatingResponseDTO: Decodable, Sendable {
    let rating: Int
    let count: Int

    private enum CodingKeys: String, CodingKey {
        case rating
        case count
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.rating = container.decodeLossyIntIfPresent(forKey: .rating) ?? 0
        self.count = container.decodeLossyIntIfPresent(forKey: .count) ?? 0
    }
}

struct ReviewRatingListResponseDTO: Decodable, Sendable {
    let data: [ReviewRatingResponseDTO]
}

struct UserReviewListResponseDTO: Decodable, Sendable {
    let data: [UserReviewResponseDTO]
    let nextCursor: String?

    private enum CodingKeys: String, CodingKey {
        case data
        case nextCursor = "next_cursor"
    }
}

struct UserReviewResponseDTO: Decodable, Sendable {
    let reviewID: String
    let content: String
    let rating: Int
    let store: CommunityStoreSummaryDTO
    let reviewImageURLs: [String]
    let orderMenuList: [String]
    let creator: UserInfoResponseDTO
    let createdAt: String?
    let updatedAt: String?

    private enum CodingKeys: String, CodingKey {
        case reviewID = "review_id"
        case id
        case content
        case rating
        case store
        case reviewImageURLs = "review_image_urls"
        case orderMenuList = "order_menu_list"
        case creator
        case createdAt
        case updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        if let reviewID = try container.decodeIfPresent(String.self, forKey: .reviewID) {
            self.reviewID = reviewID
        } else if let fallbackID = try container.decodeIfPresent(String.self, forKey: .id) {
            self.reviewID = fallbackID
        } else {
            throw DecodingError.keyNotFound(
                CodingKeys.reviewID,
                DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Missing review identifier")
            )
        }

        self.content = try container.decodeIfPresent(String.self, forKey: .content) ?? ""
        self.rating = container.decodeLossyIntIfPresent(forKey: .rating) ?? 0
        self.store = try container.decode(CommunityStoreSummaryDTO.self, forKey: .store)
        self.reviewImageURLs = try container.decodeIfPresent([String].self, forKey: .reviewImageURLs) ?? []
        self.orderMenuList = try container.decodeIfPresent([String].self, forKey: .orderMenuList) ?? []
        self.creator = try container.decode(UserInfoResponseDTO.self, forKey: .creator)
        self.createdAt = try container.decodeIfPresent(String.self, forKey: .createdAt)
        self.updatedAt = try container.decodeIfPresent(String.self, forKey: .updatedAt)
    }
}

private extension KeyedDecodingContainer {
    func decodeLossyIntIfPresent(forKey key: Key) -> Int? {
        if let value = try? decodeIfPresent(Int.self, forKey: key) {
            return value
        }
        if let value = try? decodeIfPresent(Double.self, forKey: key) {
            return Int(value)
        }
        if let value = try? decodeIfPresent(String.self, forKey: key) {
            if let intValue = Int(value) {
                return intValue
            }
            if let doubleValue = Double(value) {
                return Int(doubleValue)
            }
        }
        return nil
    }
}
