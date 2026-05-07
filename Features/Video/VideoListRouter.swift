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
            logger.warning("[VideoList] blocked selection because videoId is empty title=\(video.title)")
            return
        }

        logger.debug("[VideoList] OriginalVideo button action=openOriginal videoId=\(videoID)")
        pendingVideo = video
    }

    func clearPendingRoute() {
        pendingVideo = nil
    }
}
