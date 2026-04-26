import Foundation

struct StoreSummaryListResponseDTO: Decodable, Sendable {
    let data: [StoreSummaryDTO]
    let nextCursor: String?

    private enum CodingKeys: String, CodingKey {
        case data
        case nextCursor = "next_cursor"
    }
}

struct StoreSearchListResponseDTO: Decodable, Sendable {
    let data: [StoreSummaryDTO]
}

struct PopularStoresResponseDTO: Decodable, Sendable {
    let data: [StoreSummaryDTO]

    private enum CodingKeys: String, CodingKey {
        case data
    }

    init(data: [StoreSummaryDTO]) {
        self.data = data
    }

    init(from decoder: Decoder) throws {
        if let wrapped = try? decoder.container(keyedBy: CodingKeys.self) {
            data = try wrapped.decode([StoreSummaryDTO].self, forKey: .data)
            return
        }

        var unkeyed = try decoder.unkeyedContainer()
        var stores: [StoreSummaryDTO] = []
        while !unkeyed.isAtEnd {
            stores.append(try unkeyed.decode(StoreSummaryDTO.self))
        }
        data = stores
    }
}
