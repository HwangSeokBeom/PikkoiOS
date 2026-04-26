import Foundation

protocol ReviewRepository: Sendable {
    func uploadReviewImages(
        storeID: String,
        files: [StoreReviewUploadFile]
    ) async throws -> [String]

    func createReview(
        storeID: String,
        draft: StoreReviewDraft
    ) async throws -> UserStoreReview

    func fetchStoreReviews(
        storeID: String,
        nextCursor: String?,
        limit: Int,
        orderBy: StoreReviewSortOrder
    ) async throws -> CursorPage<StoreReview>

    func fetchReviewDetail(
        storeID: String,
        reviewID: String
    ) async throws -> UserStoreReview

    func updateReview(
        storeID: String,
        reviewID: String,
        draft: StoreReviewDraft
    ) async throws -> UserStoreReview

    func deleteReview(
        storeID: String,
        reviewID: String
    ) async throws

    func fetchStoreReviewRatings(storeID: String) async throws -> [StoreReviewRatingBreakdown]

    func fetchUserReviews(
        userID: String,
        category: String?,
        nextCursor: String?,
        limit: Int
    ) async throws -> CursorPage<UserStoreReview>
}
