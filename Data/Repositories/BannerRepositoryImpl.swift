import Foundation

struct BannerRepositoryImpl: BannerRepository {
    private let remoteDataSource: any BannerRemoteDataSourceProtocol
    private let mapper: BannerMapper

    init(
        remoteDataSource: any BannerRemoteDataSourceProtocol,
        mapper: BannerMapper
    ) {
        self.remoteDataSource = remoteDataSource
        self.mapper = mapper
    }

    func fetchMainBanners() async throws -> [Banner] {
        let response = try await remoteDataSource.fetchMainBanners()
        return response.data.map { mapper.map($0) }
    }
}
