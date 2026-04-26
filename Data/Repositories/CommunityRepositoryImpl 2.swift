import Foundation

struct CommunityRepositoryImpl: CommunityRepository {
    private let remoteDataSource: any CommunityRemoteDataSourceProtocol
    private let mapper: CommunityMapper

    init(
        remoteDataSource: any CommunityRemoteDataSourceProtocol,
        mapper: CommunityMapper
    ) {
        self.remoteDataSource = remoteDataSource
        self.mapper = mapper
    }

    func uploadPostFiles(_ files: [CommunityPostUploadFile]) async throws -> [String] {
        let response = try await remoteDataSource.uploadPostFiles(files)
        return response.files
    }

    func createPost(_ submission: CommunityPostDraftSubmission) async throws -> CommunityPostDetail {
        let response = try await remoteDataSource.createPost(try .init(submission: submission))
        return mapper.mapDetail(response)
    }

    func updatePost(postID: String, submission: CommunityPostDraftSubmission) async throws -> CommunityPostDetail {
        let response = try await remoteDataSource.updatePost(
            postID: postID,
            request: .init(submission: submission)
        )
        return mapper.mapDetail(response)
    }

    func deletePost(postID: String) async throws {
        try await remoteDataSource.deletePost(postID: postID)
    }

    func fetchPostDetail(postID: String) async throws -> CommunityPostDetail {
        let response = try await remoteDataSource.fetchPostDetail(postID: postID)
        return mapper.mapDetail(response)
    }

    func fetchComments(
        postID: String,
        nextCursor: String?,
        limit: Int
    ) async throws -> CursorPage<CommunityComment> {
        let response = try await remoteDataSource.fetchComments(
            postID: postID,
            nextCursor: nextCursor,
            limit: limit
        )
        return mapper.mapCommentPage(postID: postID, response)
    }

    func createComment(
        postID: String,
        content: String,
        parentCommentID: String?
    ) async throws -> CommunityComment {
        let response = try await remoteDataSource.createComment(
            postID: postID,
            request: CommunityCommentCreateRequestDTO(
                parentCommentID: parentCommentID,
                content: content
            )
        )
        return mapper.mapComment(
            postID: postID,
            response,
            parentCommentID: parentCommentID
        )
    }

    func updateComment(
        postID: String,
        commentID: String,
        content: String
    ) async throws -> CommunityComment {
        let response = try await remoteDataSource.updateComment(
            postID: postID,
            commentID: commentID,
            request: CommunityCommentUpdateRequestDTO(content: content)
        )
        return mapper.mapComment(postID: postID, response)
    }

    func deleteComment(
        postID: String,
        commentID: String
    ) async throws {
        try await remoteDataSource.deleteComment(
            postID: postID,
            commentID: commentID
        )
    }

    func fetchGeolocationPosts(
        category: String?,
        longitude: Double?,
        latitude: Double?,
        maxDistance: Double?,
        nextCursor: String?,
        limit: Int,
        orderBy: CommunityPostSortOrder
    ) async throws -> CursorPage<CommunityPostSummary> {
        let response = try await remoteDataSource.fetchGeolocationPosts(
            category: category,
            longitude: longitude,
            latitude: latitude,
            maxDistance: maxDistance,
            nextCursor: nextCursor,
            limit: limit,
            orderBy: orderBy
        )
        return mapper.mapPage(response)
    }

    func fetchUserPosts(
        userID: String,
        category: String?,
        nextCursor: String?,
        limit: Int
    ) async throws -> CursorPage<CommunityPostSummary> {
        let response = try await remoteDataSource.fetchUserPosts(
            userID: userID,
            category: category,
            nextCursor: nextCursor,
            limit: limit
        )
        return mapper.mapPage(response)
    }

    func fetchLikedPosts(
        category: String?,
        nextCursor: String?,
        limit: Int
    ) async throws -> CursorPage<CommunityPostSummary> {
        let response = try await remoteDataSource.fetchLikedPosts(
            category: category,
            nextCursor: nextCursor,
            limit: limit
        )
        return mapper.mapPage(response)
    }

    func searchPosts(title: String) async throws -> [CommunityPostSummary] {
        let response = try await remoteDataSource.searchPosts(title: title)
        return mapper.mapList(response)
    }

    func updateLikeStatus(postID: String, isLiked: Bool) async throws -> Bool {
        let response = try await remoteDataSource.updateLikeStatus(postID: postID, isLiked: isLiked)
        return response.likeStatus
    }
}
