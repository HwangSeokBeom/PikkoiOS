import Foundation

enum StoreSortOrder: String, Sendable {
    case distance
    case orders
    case reviews
}

protocol StoreRepository: Sendable {
    func fetchStoreDetail(storeID: String) async throws -> StoreDetail
    func searchStores(name: String?) async throws -> [StoreSummary]

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
    func fetchLikedStores(
        category: String?,
        nextCursor: String?,
        limit: Int
    ) async throws -> CursorPage<StoreSummary>
    func updateLikeStatus(storeID: String, isLiked: Bool) async throws -> Bool
}
