import Foundation

enum VideoPlaybackContext: String, Sendable {
    case shorts
    case detail
}

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
    var isScrubbing = false
    var captionsEnabled = true
    var selectedSubtitleID: String?
    var isSubtitleMenuPresented = false
    var isSubtitleLoading = false
    var subtitleErrorMessage: String?
    var activeCaptionText: String?
    var hasSystemSubtitleTracks = false

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

    var selectedSubtitleTitle: String {
        guard captionsEnabled else { return "끔" }
        guard let selectedSubtitleID,
              let subtitle = stream?.subtitles.first(where: { $0.id == selectedSubtitleID }) else {
            return hasSystemSubtitleTracks ? "시스템" : "자막"
        }
        return subtitle.name
    }

    var hasSubtitleOptions: Bool {
        stream?.subtitles.isEmpty == false || hasSystemSubtitleTracks
    }
}
