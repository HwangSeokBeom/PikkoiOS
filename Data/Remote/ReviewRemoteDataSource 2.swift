import Foundation

protocol ReviewRemoteDataSourceProtocol: Sendable {
    func uploadReviewImages(
        storeID: String,
        files: [StoreReviewUploadFile]
    ) async throws -> ReviewImageResponseDTO

    func createReview(
        storeID: String,
        request: ReviewCreateRequestDTO
    ) async throws -> UserReviewResponseDTO

    func fetchStoreReviews(
        storeID: String,
        nextCursor: String?,
        limit: Int,
        orderBy: StoreReviewSortOrder
    ) async throws -> ReviewListResponseDTO

    func fetchReviewDetail(
        storeID: String,
        reviewID: String
    ) async throws -> UserReviewResponseDTO

    func updateReview(
        storeID: String,
        reviewID: String,
        request: ReviewUpdateRequestDTO
    ) async throws -> UserReviewResponseDTO

    func deleteReview(
        storeID: String,
        reviewID: String
    ) async throws

    func fetchStoreReviewRatings(storeID: String) async throws -> ReviewRatingListResponseDTO

    func fetchUserReviews(
        userID: String,
        category: String?,
        nextCursor: String?,
        limit: Int
    ) async throws -> UserReviewListResponseDTO
}

struct ReviewRemoteDataSource: ReviewRemoteDataSourceProtocol {
    private let apiClient: any APIClientProtocol

    init(apiClient: any APIClientProtocol) {
        self.apiClient = apiClient
    }

    func uploadReviewImages(
        storeID: String,
        files: [StoreReviewUploadFile]
    ) async throws -> ReviewImageResponseDTO {
        var multipartBuilder = MultipartFormDataBuilder()
        for file in files {
            multipartBuilder.addFile(
                fieldName: "files",
                fileName: file.fileName,
                mimeType: file.mimeType,
                fileData: file.data
            )
        }

        let endpoint = Endpoint<ReviewImageResponseDTO>(
            path: "/v1/stores/\(storeID)/reviews/files",
            method: .post,
            body: multipartBuilder.build(),
            timeout: .upload,
            authorizationPolicy: .accessToken
        )
        return try await apiClient.execute(endpoint)
    }

    func createReview(
        storeID: String,
        request: ReviewCreateRequestDTO
    ) async throws -> UserReviewResponseDTO {
        let endpoint = Endpoint<UserReviewResponseDTO>(
            path: "/v1/stores/\(storeID)/reviews",
            method: .post,
            body: RequestBody.json(try NetworkCoding.makeJSONEncoder().encode(request)),
            timeout: .default,
            authorizationPolicy: .accessToken
        )
        return try await apiClient.execute(endpoint)
    }

    func fetchStoreReviews(
        storeID: String,
        nextCursor: String?,
        limit: Int,
        orderBy: StoreReviewSortOrder
    ) async throws -> ReviewListResponseDTO {
        let endpoint = Endpoint<ReviewListResponseDTO>(
            path: "/v1/stores/\(storeID)/reviews",
            method: .get,
            query: optionalQueryItems([
                ("next", nextCursor),
                ("order_by", orderBy.rawValue)
            ]) + [URLQueryItem(name: "limit", value: String(limit))],
            timeout: .default,
            authorizationPolicy: .accessToken
        )
        return try await apiClient.execute(endpoint)
    }

    func fetchReviewDetail(
        storeID: String,
        reviewID: String
    ) async throws -> UserReviewResponseDTO {
        let endpoint = Endpoint<UserReviewResponseDTO>(
            path: "/v1/stores/\(storeID)/reviews/\(reviewID)",
            method: .get,
            timeout: .default,
            authorizationPolicy: .accessToken
        )
        return try await apiClient.execute(endpoint)
    }

    func updateReview(
        storeID: String,
        reviewID: String,
        request: ReviewUpdateRequestDTO
    ) async throws -> UserReviewResponseDTO {
        let endpoint = Endpoint<UserReviewResponseDTO>(
            path: "/v1/stores/\(storeID)/reviews/\(reviewID)",
            method: .put,
            body: RequestBody.json(try NetworkCoding.makeJSONEncoder().encode(request)),
            timeout: .default,
            authorizationPolicy: .accessToken
        )
        return try await apiClient.execute(endpoint)
    }

    func deleteReview(
        storeID: String,
        reviewID: String
    ) async throws {
        let endpoint = Endpoint<EmptyResponse>(
            path: "/v1/stores/\(storeID)/reviews/\(reviewID)",
            method: .delete,
            timeout: .default,
            authorizationPolicy: .accessToken
        )
        _ = try await apiClient.execute(endpoint)
    }

    func fetchStoreReviewRatings(storeID: String) async throws -> ReviewRatingListResponseDTO {
        let endpoint = Endpoint<ReviewRatingListResponseDTO>(
            path: "/v1/stores/\(storeID)/reviews/reviews-ratings",
            method: .get,
            timeout: .default,
            authorizationPolicy: .accessToken
        )
        return try await apiClient.execute(endpoint)
    }

    func fetchUserReviews(
        userID: String,
        category: String?,
        nextCursor: String?,
        limit: Int
    ) async throws -> UserReviewListResponseDTO {
        let endpoint = Endpoint<UserReviewListResponseDTO>(
            path: "/v1/stores/reviews/users/\(userID)",
            method: .get,
            query: optionalQueryItems([
                ("category", category),
                ("next", nextCursor)
            ]) + [URLQueryItem(name: "limit", value: String(limit))],
            timeout: .default,
            authorizationPolicy: .accessToken
        )
        return try await apiClient.execute(endpoint)
    }

    private func optionalQueryItems(_ values: [(String, String?)]) -> [URLQueryItem] {
        values.compactMap { name, value in
            guard let value, !value.isEmpty else { return nil }
            return URLQueryItem(name: name, value: value)
        }
    }
}
