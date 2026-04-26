import Foundation

struct CommunityPostDetailResponseDTO: Decodable, Sendable {
    let postID: String
    let category: String?
    let title: String
    let content: String
    let store: CommunityStoreSummaryDTO?
    let geolocation: GeolocationDTO?
    let creator: CommunityUserInfoResponseDTO
    let files: [String]
    let isLike: Bool
    let likeCount: Double
    let comments: [CommunityPostCommentResponseDTO]
    let createdAt: String?
    let updatedAt: String?

    private enum CodingKeys: String, CodingKey {
        case postID = "post_id"
        case category
        case title
        case content
        case store
        case geolocation
        case creator
        case files
        case isLike = "is_like"
        case likeCount = "like_count"
        case comments
        case createdAt
        case updatedAt
    }
}

struct CommunityPostCommentResponseDTO: Decodable, Sendable {
    let commentID: String
    let content: String
    let createdAt: String?
    let creator: CommunityUserInfoResponseDTO
    let replies: [CommunityPostReplyResponseDTO]

    private enum CodingKeys: String, CodingKey {
        case commentID = "comment_id"
        case content
        case createdAt
        case creator
        case replies
    }
}

struct CommunityPostReplyResponseDTO: Decodable, Sendable {
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
