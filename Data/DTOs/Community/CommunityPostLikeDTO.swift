import Foundation

struct CommunityPostLikeRequestDTO: Encodable, Sendable {
    let likeStatus: Bool

    private enum CodingKeys: String, CodingKey {
        case likeStatus = "like_status"
    }
}

struct CommunityPostLikeResponseDTO: Decodable, Sendable {
    let likeStatus: Bool

    private enum CodingKeys: String, CodingKey {
        case likeStatus = "like_status"
    }
}
