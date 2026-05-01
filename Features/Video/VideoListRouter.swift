import Foundation

@MainActor
protocol VideoListRouting: AnyObject {
    func routeToVideoPlayer(video: Video)
    func clearPendingRoute()
}

@MainActor
final class VideoListRouter: ObservableObject, VideoListRouting {
    @Published private(set) var pendingVideo: Video?
    private let logger = Logger(category: "VideoList")

    func routeToVideoPlayer(video: Video) {
        let videoID = video.videoId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !videoID.isEmpty else {
            logger.warning("[VideoList] blocked selection because videoId is empty title=\(video.title)")
            return
        }

        pendingVideo = video
    }

    func clearPendingRoute() {
        pendingVideo = nil
    }
}
