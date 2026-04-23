import Foundation

protocol BannerRemoteDataSourceProtocol: Sendable {
    func fetchMainBanners() async throws -> BannerListResponseDTO
}

struct BannerRemoteDataSource: BannerRemoteDataSourceProtocol {
    private let apiClient: any APIClientProtocol

    init(apiClient: any APIClientProtocol) {
        self.apiClient = apiClient
    }

    func fetchMainBanners() async throws -> BannerListResponseDTO {
        let endpoint = Endpoint<BannerListResponseDTO>(
            path: "/v1/banners/main",
            method: .get,
            timeout: .default,
            authorizationPolicy: .accessToken
        )
        return try await apiClient.execute(endpoint)
    }
}
