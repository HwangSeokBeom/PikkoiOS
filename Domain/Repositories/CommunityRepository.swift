import Foundation

enum CommunityPostSortOrder: String, Sendable {
    case createdAt
    case likes
}

protocol CommunityRepository: Sendable {
    func uploadPostFiles(_ files: [CommunityPostUploadFile]) async throws -> [String]
    func createPost(_ submission: CommunityPostDraftSubmission) async throws -> CommunityPostDetail
    func updatePost(postID: String, submission: CommunityPostDraftSubmission) async throws -> CommunityPostDetail
    func deletePost(postID: String) async throws
    func fetchPostDetail(postID: String) async throws -> CommunityPostDetail
    func fetchComments(
        postID: String,
        nextCursor: String?,
        limit: Int
    ) async throws -> CursorPage<CommunityComment>
    func createComment(
        postID: String,
        content: String,
        parentCommentID: String?
    ) async throws -> CommunityComment
    func updateComment(
        postID: String,
        commentID: String,
        content: String
    ) async throws -> CommunityComment
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
    ) async throws -> CursorPage<CommunityPostSummary>

    func fetchUserPosts(
        userID: String,
        category: String?,
        nextCursor: String?,
        limit: Int
    ) async throws -> CursorPage<CommunityPostSummary>

    func fetchLikedPosts(
        category: String?,
        nextCursor: String?,
        limit: Int
    ) async throws -> CursorPage<CommunityPostSummary>

    func searchPosts(title: String) async throws -> [CommunityPostSummary]
    func updateLikeStatus(postID: String, isLiked: Bool) async throws -> Bool
}
