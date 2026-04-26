import Foundation

struct StoreRepositoryImpl: StoreRepository {
    private let remoteDataSource: any StoreRemoteDataSourceProtocol
    private let mapper: StoreMapper

    init(
        remoteDataSource: any StoreRemoteDataSourceProtocol,
        mapper: StoreMapper
    ) {
        self.remoteDataSource = remoteDataSource
        self.mapper = mapper
    }

    func fetchStoreDetail(storeID: String) async throws -> StoreDetail {
        let response = try await remoteDataSource.fetchStoreDetail(storeID: storeID)
        return mapper.mapDetail(response)
    }

    func searchStores(name: String?) async throws -> [StoreSummary] {
        let response = try await remoteDataSource.searchStores(name: name)
        return response.data.map { mapper.map($0) }
    }

    func fetchNearbyStores(
        category: String?,
        longitude: Double?,
        latitude: Double?,
        maxDistance: Double?,
        nextCursor: String?,
        limit: Int,
        orderBy: StoreSortOrder
    ) async throws -> CursorPage<StoreSummary> {
        let response = try await remoteDataSource.fetchNearbyStores(
            category: category,
            longitude: longitude,
            latitude: latitude,
            maxDistance: maxDistance,
            nextCursor: nextCursor,
            limit: limit,
            orderBy: orderBy
        )
        return mapper.mapPage(response)
    }

    func fetchPopularStores(category: String?) async throws -> [StoreSummary] {
        let response = try await remoteDataSource.fetchPopularStores(category: category)
        return response.data.map { mapper.map($0) }
    }

    func fetchPopularSearchTerms() async throws -> [String] {
        let response = try await remoteDataSource.fetchPopularSearchTerms()
        return response.data
    }

    func fetchLikedStores(
        category: String?,
        nextCursor: String?,
        limit: Int
    ) async throws -> CursorPage<StoreSummary> {
        let response = try await remoteDataSource.fetchLikedStores(
            category: category,
            nextCursor: nextCursor,
            limit: limit
        )
        return mapper.mapPage(response)
    }

    func updateLikeStatus(storeID: String, isLiked: Bool) async throws -> Bool {
        let response = try await remoteDataSource.updateLikeStatus(storeID: storeID, isLiked: isLiked)
        return response.likeStatus
    }
}
