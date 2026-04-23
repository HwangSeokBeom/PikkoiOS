import Foundation

struct LikeStoreRequestDTO: Encodable, Sendable {
    let likeStatus: Bool

    private enum CodingKeys: String, CodingKey {
        case likeStatus = "like_status"
    }
}

struct LikeStoreResponseDTO: Decodable, Sendable {
    let likeStatus: Bool

    private enum CodingKeys: String, CodingKey {
        case likeStatus = "like_status"
    }
}
