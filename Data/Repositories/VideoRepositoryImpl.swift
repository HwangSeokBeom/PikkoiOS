import Foundation

struct VideoRepositoryImpl: VideoRepository {
    private let remoteDataSource: any VideoRemoteDataSourceProtocol
    private let mapper: VideoMapper

    init(
        remoteDataSource: any VideoRemoteDataSourceProtocol,
        mapper: VideoMapper
    ) {
        self.remoteDataSource = remoteDataSource
        self.mapper = mapper
    }

    func fetchVideos(nextCursor: String?, limit: Int) async throws -> CursorPage<Video> {
        let response = try await remoteDataSource.fetchVideos(nextCursor: nextCursor, limit: limit)
        return mapper.mapPage(response)
    }

    func fetchVideoStream(videoId: String) async throws -> VideoStream {
        let response = try await remoteDataSource.fetchVideoStream(videoId: videoId)
        return try mapper.map(response)
    }

    func updateLikeStatus(videoId: String, isLiked: Bool) async throws -> Bool {
        let response = try await remoteDataSource.updateLikeStatus(videoId: videoId, isLiked: isLiked)
        return response.likeStatus
    }
}
