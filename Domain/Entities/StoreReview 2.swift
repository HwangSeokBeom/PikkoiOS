import Foundation

enum StoreReviewSortOrder: String, Sendable {
    case latest
    case ratingHigh = "rating_high"
    case ratingLow = "rating_low"
}

struct StoreReview: Equatable, Sendable {
    let id: String
    let content: String
    let rating: Int
    let imagePaths: [String]
    let orderedMenuNames: [String]
    let author: StoreReviewAuthor
    let userTotalReviewCount: Int
    let userAverageRating: Double?
    let createdAt: Date?
    let updatedAt: Date?
}

struct StoreReviewUploadFile: Equatable, Sendable {
    let data: Data
    let fileName: String
    let mimeType: String
}

struct StoreReviewDraft: Equatable, Sendable {
    let content: String
    let rating: Int
    let imagePaths: [String]
    let orderCode: String?
}

struct UserStoreReview: Equatable, Sendable, Identifiable {
    let id: String
    let store: CommunityPostStoreSummary
    let content: String
    let rating: Int
    let imagePaths: [String]
    let orderedMenuNames: [String]
    let author: StoreReviewAuthor
    let createdAt: Date?
    let updatedAt: Date?
}

struct StoreReviewAuthor: Equatable, Sendable {
    let id: String
    let nick: String
    let profileImagePath: String?
}

struct StoreReviewRatingBreakdown: Equatable, Sendable {
    let rating: Int
    let count: Int
}
