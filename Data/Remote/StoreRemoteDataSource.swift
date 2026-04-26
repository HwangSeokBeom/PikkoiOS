import Foundation

protocol StoreRemoteDataSourceProtocol: Sendable {
    func fetchStoreDetail(storeID: String) async throws -> StoreDetailResponseDTO
    func searchStores(name: String?) async throws -> StoreSearchListResponseDTO
    func fetchLikedStores(
        category: String?,
        nextCursor: String?,
        limit: Int
    ) async throws -> StoreSummaryListResponseDTO

    func fetchNearbyStores(
        category: String?,
        longitude: Double?,
        latitude: Double?,
        maxDistance: Double?,
        nextCursor: String?,
        limit: Int,
        orderBy: StoreSortOrder
    ) async throws -> StoreSummaryListResponseDTO

    func fetchPopularStores(category: String?) async throws -> PopularStoresResponseDTO
    func fetchPopularSearchTerms() async throws -> PopularSearchTermsResponseDTO
    func updateLikeStatus(storeID: String, isLiked: Bool) async throws -> LikeStoreResponseDTO
}

struct StoreRemoteDataSource: StoreRemoteDataSourceProtocol {
    private let apiClient: any APIClientProtocol

    init(apiClient: any APIClientProtocol) {
        self.apiClient = apiClient
    }

    func fetchStoreDetail(storeID: String) async throws -> StoreDetailResponseDTO {
        let endpoint = Endpoint<StoreDetailResponseDTO>(
            path: "/v1/stores/\(storeID)",
            method: .get,
            timeout: .default,
            authorizationPolicy: .accessToken
        )
        return try await apiClient.execute(endpoint)
    }

    func searchStores(name: String?) async throws -> StoreSearchListResponseDTO {
        let endpoint = Endpoint<StoreSearchListResponseDTO>(
            path: "/v1/stores/search",
            method: .get,
            query: optionalQueryItems([("name", name)]),
            timeout: .default,
            authorizationPolicy: .accessToken
        )
        return try await apiClient.execute(endpoint)
    }

    func fetchLikedStores(
        category: String?,
        nextCursor: String?,
        limit: Int
    ) async throws -> StoreSummaryListResponseDTO {
        let endpoint = Endpoint<StoreSummaryListResponseDTO>(
            path: "/v1/stores/likes/me",
            method: .get,
            query: optionalQueryItems([
                ("category", category),
                ("next", nextCursor),
                ("limit", String(limit))
            ]),
            timeout: .default,
            authorizationPolicy: .accessToken
        )
        return try await apiClient.execute(endpoint)
    }

    func fetchNearbyStores(
        category: String?,
        longitude: Double?,
        latitude: Double?,
        maxDistance: Double?,
        nextCursor: String?,
        limit: Int,
        orderBy: StoreSortOrder
    ) async throws -> StoreSummaryListResponseDTO {
        let endpoint = Endpoint<StoreSummaryListResponseDTO>(
            path: "/v1/stores",
            method: .get,
            query: makeNearbyStoreQuery(
                category: category,
                longitude: longitude,
                latitude: latitude,
                maxDistance: maxDistance,
                nextCursor: nextCursor,
                limit: limit,
                orderBy: orderBy
            ),
            timeout: .default,
            authorizationPolicy: .accessToken
        )
        return try await apiClient.execute(endpoint)
    }

    func fetchPopularStores(category: String?) async throws -> PopularStoresResponseDTO {
        let endpoint = Endpoint<PopularStoresResponseDTO>(
            path: "/v1/stores/popular-stores",
            method: .get,
            query: optionalQueryItems([("category", category)]),
            timeout: .default,
            authorizationPolicy: .accessToken
        )
        return try await apiClient.execute(endpoint)
    }

    func fetchPopularSearchTerms() async throws -> PopularSearchTermsResponseDTO {
        let endpoint = Endpoint<PopularSearchTermsResponseDTO>(
            path: "/v1/stores/searches-popular",
            method: .get,
            timeout: .default,
            authorizationPolicy: .accessToken
        )
        return try await apiClient.execute(endpoint)
    }

    func updateLikeStatus(storeID: String, isLiked: Bool) async throws -> LikeStoreResponseDTO {
        let body = RequestBody.json(try JSONEncoder().encode(LikeStoreRequestDTO(likeStatus: isLiked)))
        let endpoint = Endpoint<LikeStoreResponseDTO>(
            path: "/v1/stores/\(storeID)/like",
            method: .post,
            body: body,
            timeout: .default,
            authorizationPolicy: .accessToken
        )
        return try await apiClient.execute(endpoint)
    }

    private func makeNearbyStoreQuery(
        category: String?,
        longitude: Double?,
        latitude: Double?,
        maxDistance: Double?,
        nextCursor: String?,
        limit: Int,
        orderBy: StoreSortOrder
    ) -> [URLQueryItem] {
        var queryItems = optionalQueryItems([
            ("category", category),
            ("longitude", longitude.map(Self.stringify)),
            ("latitude", latitude.map(Self.stringify)),
            ("maxDistance", maxDistance.map(Self.stringify)),
            ("next", nextCursor)
        ])

        queryItems.append(URLQueryItem(name: "limit", value: String(limit)))
        queryItems.append(URLQueryItem(name: "order_by", value: orderBy.rawValue))
        return queryItems
    }

    private func optionalQueryItems(_ values: [(String, String?)]) -> [URLQueryItem] {
        values.compactMap { name, value in
            guard let value, !value.isEmpty else { return nil }
            return URLQueryItem(name: name, value: value)
        }
    }

    private static func stringify(_ value: Double) -> String {
        if value.rounded() == value {
            return String(Int(value))
        }
        return String(value)
    }
}
