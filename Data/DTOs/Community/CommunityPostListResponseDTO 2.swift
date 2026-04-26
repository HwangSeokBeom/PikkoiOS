import Foundation

struct CommunityPostSummaryPaginationResponseDTO: Decodable, Sendable {
    let data: [CommunityPostSummaryResponseDTO]
    let nextCursor: String?

    private enum CodingKeys: String, CodingKey {
        case data
        case nextCursor = "next_cursor"
    }
}

struct CommunityPostSummaryListResponseDTO: Decodable, Sendable {
    let data: [CommunityPostSummaryResponseDTO]
}
