import Foundation

struct CommunityCommentPageResponseDTO: Decodable, Sendable {
    let data: [CommunityPostCommentResponseDTO]
    let nextCursor: String?

    init(
        data: [CommunityPostCommentResponseDTO],
        nextCursor: String? = nil
    ) {
        self.data = data
        self.nextCursor = nextCursor
    }
}

struct CommunityCommentMutationResponseDTO: Decodable, Sendable {
    let commentID: String
    let content: String
    let createdAt: String?
    let creator: CommunityUserInfoResponseDTO

    private enum CodingKeys: String, CodingKey {
        case commentID = "comment_id"
        case content
        case createdAt
        case creator
    }
}

struct CommunityCommentCreateRequestDTO: Encodable, Sendable {
    let parentCommentID: String?
    let content: String

    private enum CodingKeys: String, CodingKey {
        case parentCommentID = "parent_comment_id"
        case content
    }
}

struct CommunityCommentUpdateRequestDTO: Encodable, Sendable {
    let content: String
}
