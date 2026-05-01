import Foundation

@MainActor
protocol VideoListInteracting {
    func loadVideos(nextCursor: String?, limit: Int) async throws -> CursorPage<Video>
    func updateVideoLikeStatus(videoID: String, isLiked: Bool) async throws -> Bool
}

@MainActor
struct VideoListInteractor: VideoListInteracting {
    private let fetchVideosUseCase: FetchVideosUseCase
    private let setVideoLikeUseCase: SetVideoLikeUseCase

    init(
        fetchVideosUseCase: FetchVideosUseCase,
        setVideoLikeUseCase: SetVideoLikeUseCase
    ) {
        self.fetchVideosUseCase = fetchVideosUseCase
        self.setVideoLikeUseCase = setVideoLikeUseCase
    }

    func loadVideos(nextCursor: String?, limit: Int) async throws -> CursorPage<Video> {
        try await fetchVideosUseCase.execute(nextCursor: nextCursor, limit: limit)
    }

    func updateVideoLikeStatus(videoID: String, isLiked: Bool) async throws -> Bool {
        try await setVideoLikeUseCase.execute(videoId: videoID, isLiked: isLiked)
    }
}
