import Foundation

struct ReviewRepositoryImpl: ReviewRepository {
    private let remoteDataSource: any ReviewRemoteDataSourceProtocol
    private let mapper: ReviewMapper

    init(
        remoteDataSource: any ReviewRemoteDataSourceProtocol,
        mapper: ReviewMapper
    ) {
        self.remoteDataSource = remoteDataSource
        self.mapper = mapper
    }

    func uploadReviewImages(
        storeID: String,
        files: [StoreReviewUploadFile]
    ) async throws -> [String] {
        let response = try await remoteDataSource.uploadReviewImages(storeID: storeID, files: files)
        return response.reviewImageURLs.map(mapper.normalizedServerPath(from:))
    }

    func createReview(
        storeID: String,
        draft: StoreReviewDraft
    ) async throws -> UserStoreReview {
        guard let orderCode = draft.orderCode?.trimmingCharacters(in: .whitespacesAndNewlines),
              !orderCode.isEmpty else {
            throw NetworkError.invalidRequest
        }

        let response = try await remoteDataSource.createReview(
            storeID: storeID,
            request: ReviewCreateRequestDTO(
                content: draft.content,
                rating: draft.rating,
                reviewImageURLs: draft.imagePaths,
                orderCode: orderCode
            )
        )
        return mapper.mapUserReview(response)
    }

    func fetchStoreReviews(
        storeID: String,
        nextCursor: String?,
        limit: Int,
        orderBy: StoreReviewSortOrder
    ) async throws -> CursorPage<StoreReview> {
        let response = try await remoteDataSource.fetchStoreReviews(
            storeID: storeID,
            nextCursor: nextCursor,
            limit: limit,
            orderBy: orderBy
        )
        return mapper.mapPage(response)
    }

    func fetchReviewDetail(
        storeID: String,
        reviewID: String
    ) async throws -> UserStoreReview {
        let response = try await remoteDataSource.fetchReviewDetail(storeID: storeID, reviewID: reviewID)
        return mapper.mapUserReview(response)
    }

    func updateReview(
        storeID: String,
        reviewID: String,
        draft: StoreReviewDraft
    ) async throws -> UserStoreReview {
        let response = try await remoteDataSource.updateReview(
            storeID: storeID,
            reviewID: reviewID,
            request: ReviewUpdateRequestDTO(
                content: draft.content,
                rating: draft.rating,
                reviewImageURLs: draft.imagePaths
            )
        )
        return mapper.mapUserReview(response)
    }

    func deleteReview(
        storeID: String,
        reviewID: String
    ) async throws {
        try await remoteDataSource.deleteReview(storeID: storeID, reviewID: reviewID)
    }

    func fetchStoreReviewRatings(storeID: String) async throws -> [StoreReviewRatingBreakdown] {
        let response = try await remoteDataSource.fetchStoreReviewRatings(storeID: storeID)
        return mapper.mapRatings(response)
    }

    func fetchUserReviews(
        userID: String,
        category: String?,
        nextCursor: String?,
        limit: Int
    ) async throws -> CursorPage<UserStoreReview> {
        let response = try await remoteDataSource.fetchUserReviews(
            userID: userID,
            category: category,
            nextCursor: nextCursor,
            limit: limit
        )
        return mapper.mapUserReviewPage(response)
    }
}
