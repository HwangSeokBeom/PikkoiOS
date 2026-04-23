import Foundation

struct BannerPayloadDTO: Decodable, Sendable {
    let type: String
    let value: String
}

struct BannerResponseDTO: Decodable, Sendable {
    let name: String
    let imageURL: String
    let payload: BannerPayloadDTO

    private enum CodingKeys: String, CodingKey {
        case name
        case imageURL = "imageUrl"
        case payload
    }
}

struct BannerListResponseDTO: Decodable, Sendable {
    let data: [BannerResponseDTO]
}
