import Foundation

struct StoreSummaryListResponseDTO: Decodable, Sendable {
    let data: [StoreSummaryDTO]
    let nextCursor: String?

    private enum CodingKeys: String, CodingKey {
        case data
        case nextCursor = "next_cursor"
    }
}
