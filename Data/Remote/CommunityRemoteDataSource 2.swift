import Foundation

protocol CommunityRemoteDataSourceProtocol: Sendable {
    func uploadPostFiles(_ files: [CommunityPostUploadFile]) async throws -> CommunityFileUploadResponseDTO
    func createPost(_ request: CommunityPostCreateRequestDTO) async throws -> CommunityPostDetailResponseDTO
    func updatePost(postID: String, request: CommunityPostUpdateRequestDTO) async throws -> CommunityPostDetailResponseDTO
    func deletePost(postID: String) async throws
    func fetchPostDetail(postID: String) async throws -> CommunityPostDetailResponseDTO
    func fetchComments(
        postID: String,
        nextCursor: String?,
        limit: Int
    ) async throws -> CommunityCommentPageResponseDTO
    func createComment(
        postID: String,
        request: CommunityCommentCreateRequestDTO
    ) async throws -> CommunityCommentMutationResponseDTO
    func updateComment(
        postID: String,
        commentID: String,
        request: CommunityCommentUpdateRequestDTO
    ) async throws -> CommunityCommentMutationResponseDTO
    func deleteComment(
        postID: String,
        commentID: String
    ) async throws

    func fetchGeolocationPosts(
        category: String?,
        longitude: Double?,
        latitude: Double?,
        maxDistance: Double?,
        nextCursor: String?,
        limit: Int,
        orderBy: CommunityPostSortOrder
    ) async throws -> CommunityPostSummaryPaginationResponseDTO

    func fetchUserPosts(
        userID: String,
        category: String?,
        nextCursor: String?,
        limit: Int
    ) async throws -> CommunityPostSummaryPaginationResponseDTO

    func fetchLikedPosts(
        category: String?,
        nextCursor: String?,
        limit: Int
    ) async throws -> CommunityPostSummaryPaginationResponseDTO

    func searchPosts(title: String) async throws -> CommunityPostSummaryListResponseDTO
    func updateLikeStatus(postID: String, isLiked: Bool) async throws -> CommunityPostLikeResponseDTO
}

struct CommunityRemoteDataSource: CommunityRemoteDataSourceProtocol {
    private let apiClient: any APIClientProtocol

    init(apiClient: any APIClientProtocol) {
        self.apiClient = apiClient
    }

    func uploadPostFiles(_ files: [CommunityPostUploadFile]) async throws -> CommunityFileUploadResponseDTO {
        var multipartBuilder = MultipartFormDataBuilder()
        for file in files {
            multipartBuilder.addFile(
                fieldName: "files",
                fileName: file.fileName,
                mimeType: file.mimeType,
                fileData: file.data
            )
        }

        let endpoint = Endpoint<CommunityFileUploadResponseDTO>(
            path: "/v1/posts/files",
            method: .post,
            body: multipartBuilder.build(),
            timeout: .upload,
            authorizationPolicy: .accessToken
        )
        return try await apiClient.execute(endpoint)
    }

    func createPost(_ request: CommunityPostCreateRequestDTO) async throws -> CommunityPostDetailResponseDTO {
        let body = RequestBody.json(try JSONEncoder().encode(request))
        let endpoint = Endpoint<CommunityPostDetailResponseDTO>(
            path: "/v1/posts",
            method: .post,
            body: body,
            timeout: .default,
            authorizationPolicy: .accessToken
        )
        return try await apiClient.execute(endpoint)
    }

    func updatePost(postID: String, request: CommunityPostUpdateRequestDTO) async throws -> CommunityPostDetailResponseDTO {
        let body = RequestBody.json(try JSONEncoder().encode(request))
        let endpoint = Endpoint<CommunityPostDetailResponseDTO>(
            path: "/v1/posts/\(postID)",
            method: .put,
            body: body,
            timeout: .default,
            authorizationPolicy: .accessToken
        )
        return try await apiClient.execute(endpoint)
    }

    func deletePost(postID: String) async throws {
        let endpoint = Endpoint<EmptyResponse>(
            path: "/v1/posts/\(postID)",
            method: .delete,
            timeout: .default,
            authorizationPolicy: .accessToken
        )
        _ = try await apiClient.execute(endpoint)
    }

    func fetchPostDetail(postID: String) async throws -> CommunityPostDetailResponseDTO {
        let endpoint = Endpoint<CommunityPostDetailResponseDTO>(
            path: "/v1/posts/\(postID)",
            method: .get,
            timeout: .default,
            authorizationPolicy: .accessToken
        )
        return try await apiClient.execute(endpoint)
    }

    func fetchComments(
        postID: String,
        nextCursor: String?,
        limit: Int
    ) async throws -> CommunityCommentPageResponseDTO {
        _ = nextCursor
        _ = limit

        // TODO: Replace with dedicated paginated comments endpoint when the server exposes one.
        let detail = try await fetchPostDetail(postID: postID)
        return CommunityCommentPageResponseDTO(
            data: detail.comments,
            nextCursor: nil
        )
    }

    func createComment(
        postID: String,
        request: CommunityCommentCreateRequestDTO
    ) async throws -> CommunityCommentMutationResponseDTO {
        let body = RequestBody.json(try JSONEncoder().encode(request))
        let endpoint = Endpoint<CommunityCommentMutationResponseDTO>(
            path: "/v1/posts/\(postID)/comments",
            method: .post,
            body: body,
            timeout: .default,
            authorizationPolicy: .accessToken
        )
        return try await apiClient.execute(endpoint)
    }

    func updateComment(
        postID: String,
        commentID: String,
        request: CommunityCommentUpdateRequestDTO
    ) async throws -> CommunityCommentMutationResponseDTO {
        let body = RequestBody.json(try JSONEncoder().encode(request))
        let endpoint = Endpoint<CommunityCommentMutationResponseDTO>(
            path: "/v1/posts/\(postID)/comments/\(commentID)",
            method: .put,
            body: body,
            timeout: .default,
            authorizationPolicy: .accessToken
        )
        return try await apiClient.execute(endpoint)
    }

    func deleteComment(
        postID: String,
        commentID: String
    ) async throws {
        let endpoint = Endpoint<EmptyResponse>(
            path: "/v1/posts/\(postID)/comments/\(commentID)",
            method: .delete,
            timeout: .default,
            authorizationPolicy: .accessToken
        )
        _ = try await apiClient.execute(endpoint)
    }

    func fetchGeolocationPosts(
        category: String?,
        longitude: Double?,
        latitude: Double?,
        maxDistance: Double?,
        nextCursor: String?,
        limit: Int,
        orderBy: CommunityPostSortOrder
    ) async throws -> CommunityPostSummaryPaginationResponseDTO {
        let endpoint = Endpoint<CommunityPostSummaryPaginationResponseDTO>(
            path: "/v1/posts/geolocation",
            method: .get,
            query: makeGeolocationQuery(
                category: category,
                longitude: longitude,
                latitude: latitude,
                maxDistance: maxDistance,
                nextCursor: nextCursor,
                limit: limit,
                orderBy: orderBy
            ),
            timeout: .default,
            authorizationPolicy: .accessToken
        )
        return try await apiClient.execute(endpoint)
    }

    func fetchUserPosts(
        userID: String,
        category: String?,
        nextCursor: String?,
        limit: Int
    ) async throws -> CommunityPostSummaryPaginationResponseDTO {
        let endpoint = Endpoint<CommunityPostSummaryPaginationResponseDTO>(
            path: "/v1/posts/users/\(userID)",
            method: .get,
            query: makePaginationQuery(
                category: category,
                nextCursor: nextCursor,
                limit: limit
            ),
            timeout: .default,
            authorizationPolicy: .accessToken
        )
        return try await apiClient.execute(endpoint)
    }

    func fetchLikedPosts(
        category: String?,
        nextCursor: String?,
        limit: Int
    ) async throws -> CommunityPostSummaryPaginationResponseDTO {
        let endpoint = Endpoint<CommunityPostSummaryPaginationResponseDTO>(
            path: "/v1/posts/likes/me",
            method: .get,
            query: makePaginationQuery(
                category: category,
                nextCursor: nextCursor,
                limit: limit
            ),
            timeout: .default,
            authorizationPolicy: .accessToken
        )
        return try await apiClient.execute(endpoint)
    }

    func searchPosts(title: String) async throws -> CommunityPostSummaryListResponseDTO {
        let endpoint = Endpoint<CommunityPostSummaryListResponseDTO>(
            path: "/v1/posts/search",
            method: .get,
            query: [URLQueryItem(name: "title", value: title)],
            timeout: .default,
            authorizationPolicy: .accessToken
        )
        return try await apiClient.execute(endpoint)
    }

    func updateLikeStatus(postID: String, isLiked: Bool) async throws -> CommunityPostLikeResponseDTO {
        let body = RequestBody.json(try JSONEncoder().encode(CommunityPostLikeRequestDTO(likeStatus: isLiked)))
        let endpoint = Endpoint<CommunityPostLikeResponseDTO>(
            path: "/v1/posts/\(postID)/like",
            method: .post,
            body: body,
            timeout: .default,
            authorizationPolicy: .accessToken
        )
        return try await apiClient.execute(endpoint)
    }

    private func makePaginationQuery(
        category: String?,
        nextCursor: String?,
        limit: Int
    ) -> [URLQueryItem] {
        var queryItems = optionalQueryItems([
            ("category", category),
            ("next", nextCursor)
        ])

        queryItems.append(URLQueryItem(name: "limit", value: String(limit)))
        return queryItems
    }

    private func makeGeolocationQuery(
        category: String?,
        longitude: Double?,
        latitude: Double?,
        maxDistance: Double?,
        nextCursor: String?,
        limit: Int,
        orderBy: CommunityPostSortOrder
    ) -> [URLQueryItem] {
        var queryItems = optionalQueryItems([
            ("category", category),
            ("longitude", longitude.map(Self.stringify)),
            ("latitude", latitude.map(Self.stringify)),
            ("maxDistance", maxDistance.map(Self.stringify)),
            ("next", nextCursor)
        ])

        queryItems.append(URLQueryItem(name: "limit", value: String(limit)))
        queryItems.append(URLQueryItem(name: "order_by", value: orderBy.rawValue))
        return queryItems
    }

    private func optionalQueryItems(_ values: [(String, String?)]) -> [URLQueryItem] {
        values.compactMap { name, value in
            guard let value, !value.isEmpty else { return nil }
            return URLQueryItem(name: name, value: value)
        }
    }

    private static func stringify(_ value: Double) -> String {
        if value.rounded() == value {
            return String(Int(value))
        }
        return String(value)
    }
}
