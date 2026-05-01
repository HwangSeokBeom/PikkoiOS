import Foundation

protocol VideoRemoteDataSourceProtocol: Sendable {
    func fetchVideos(nextCursor: String?, limit: Int) async throws -> VideoListResponseDTO
    func fetchVideoStream(videoId: String) async throws -> StreamUrlResponseDTO
    func updateLikeStatus(videoId: String, isLiked: Bool) async throws -> VideoLikeResponseDTO
}

struct VideoRemoteDataSource: VideoRemoteDataSourceProtocol {
    private let apiClient: any APIClientProtocol
    private let logger = Logger(category: "VideoAPI")

    init(apiClient: any APIClientProtocol) {
        self.apiClient = apiClient
    }

    func fetchVideos(nextCursor: String?, limit: Int) async throws -> VideoListResponseDTO {
        logger.debug("[VideoAPI] request list limit=\(limit) next=\(nextCursor ?? "nil")")
        let response = try await apiClient.execute(VideoEndpoint.list(nextCursor: nextCursor, limit: limit))
        logger.debug("[VideoAPI] response list count=\(response.data.count) nextCursor=\(response.nextCursor ?? "nil")")
        return response
    }

    func fetchVideoStream(videoId: String) async throws -> StreamUrlResponseDTO {
        let normalizedVideoId = videoId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedVideoId.isEmpty else {
            logger.error("[VideoAPI] invalid empty videoId")
            throw VideoStreamRequestError.invalidVideoId
        }

        logger.debug("[VideoAPI] request stream videoID=\(normalizedVideoId)")
        do {
            let response = try await apiClient.execute(try VideoEndpoint.stream(videoId: normalizedVideoId))
            logger.debug(
                "[VideoAPI] response stream videoID=\(response.videoId) streamURLExists=\(!response.streamURLPath.isEmpty) qualities=\(response.qualities.map(\.quality).joined(separator: ","))"
            )
            logger.debug(
                "[VideoPlayer] ready videoID=\(response.videoId) qualities=\(response.qualities.map(\.quality).joined(separator: ",")) subtitles=\(response.subtitles.count)"
            )
            return response
        } catch NetworkError.forbidden {
            logger.warning("[VideoPlayer] stream forbidden videoId=\(normalizedVideoId) keepSession=true")
            throw NetworkError.forbidden
        }
    }

    func updateLikeStatus(videoId: String, isLiked: Bool) async throws -> VideoLikeResponseDTO {
        logger.debug("[VideoLike] request videoId=\(videoId) nextLikeStatus=\(isLiked)")
        let response = try await apiClient.execute(try VideoEndpoint.like(videoId: videoId, isLiked: isLiked))
        logger.debug("[VideoLike] response videoId=\(videoId) likeStatus=\(response.likeStatus)")
        return response
    }
}
