import Foundation

enum VideoPlayerPlaybackState: Equatable {
    case idle
    case loadingStream
    case ready
    case playing
    case paused
    case failed(String)
    case expiredOrUnavailable(String)
}

struct VideoPlayerViewState: Equatable {
    var video: Video
    var playbackState: VideoPlayerPlaybackState = .idle
    var stream: VideoStream?
    var userSelectedQuality: String = "auto"
    var effectivePlaybackQuality: String?
    var detailReason: String?
    var isQualityMenuPresented = false
    var isLikeUpdating = false
    var toastMessage: String?
    var currentTime: Double = 0
    var duration: Double?

    var qualityTitle: String {
        if userSelectedQuality == "auto" {
            if let effectivePlaybackQuality,
               effectivePlaybackQuality != "auto" {
                return "자동(\(effectivePlaybackQuality))"
            }
            return "자동"
        }
        return userSelectedQuality
    }

    var playbackProgress: Double {
        guard let duration, duration.isFinite, duration > 0 else {
            return 0
        }
        return min(max(currentTime / duration, 0), 1)
    }
}
