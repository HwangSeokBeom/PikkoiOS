import Foundation

struct StoreSummary: Equatable, Sendable {
    let id: String
    let category: String?
    let name: String
    let closeTime: String?
    let imagePaths: [String]
    let isPicchelin: Bool
    let isLiked: Bool
    let likeCount: Int
    let hashTags: [String]
    let totalRating: Double?
    let totalOrderCount: Int
    let totalReviewCount: Int
    let longitude: Double?
    let latitude: Double?
    let distanceMeters: Double?
}
