import Foundation

enum StoreSortOrder: String, Sendable {
    case distance
    case orders
    case reviews
}

protocol StoreRepository: Sendable {
    func fetchNearbyStores(
        category: String?,
        longitude: Double?,
        latitude: Double?,
        maxDistance: Double?,
        nextCursor: String?,
        limit: Int,
        orderBy: StoreSortOrder
    ) async throws -> CursorPage<StoreSummary>

    func fetchPopularStores(category: String?) async throws -> [StoreSummary]
    func fetchPopularSearchTerms() async throws -> [String]
    func updateLikeStatus(storeID: String, isLiked: Bool) async throws -> Bool
}
