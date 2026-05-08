import Foundation

@MainActor
protocol VideoListRouting: AnyObject {
    func routeToOriginalVideo(video: Video)
    func clearPendingRoute()
}

@MainActor
final class VideoListRouter: ObservableObject, VideoListRouting {
    @Published private(set) var pendingVideo: Video?
    private let logger = Logger(category: "VideoList")

    func routeToOriginalVideo(video: Video) {
        let videoID = video.videoId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !videoID.isEmpty else {
            logger.warning("[ShortsOriginal] open failed reason=missingVideoId")
            return
        }
        if pendingVideo?.videoId == videoID {
            logger.debug("[RouteGuard] append skipped reason=duplicate destination=videoDetail videoId=\(videoID)")
            return
        }

        logger.debug("[RouteGuard] mutation serialized destination=videoDetail videoId=\(videoID)")
        pendingVideo = video
    }

    func clearPendingRoute() {
        pendingVideo = nil
    }
}
