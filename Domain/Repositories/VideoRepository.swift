import Foundation

protocol VideoRepository: Sendable {
    func fetchVideos(nextCursor: String?, limit: Int) async throws -> CursorPage<Video>
    func fetchVideoStream(videoId: String) async throws -> VideoStream
    func updateLikeStatus(videoId: String, isLiked: Bool) async throws -> Bool
}
