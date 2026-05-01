import Foundation

struct VideoStream: Equatable, Sendable {
    let videoId: String
    let streamURL: URL
    let streamURLPath: String
    let defaultQuality: String?
    let qualities: [VideoStreamQuality]
    let subtitles: [VideoSubtitle]

    init(
        videoId: String,
        streamURL: URL,
        streamURLPath: String? = nil,
        defaultQuality: String? = nil,
        qualities: [VideoStreamQuality],
        subtitles: [VideoSubtitle]
    ) {
        self.videoId = videoId
        self.streamURL = streamURL
        self.streamURLPath = streamURLPath ?? streamURL.absoluteString
        self.defaultQuality = defaultQuality
        self.qualities = qualities
        self.subtitles = subtitles
    }

    init(
        videoId: String,
        streamURL: URL,
        qualities: [VideoStreamQuality],
        subtitles: [VideoSubtitle]
    ) {
        self.init(
            videoId: videoId,
            streamURL: streamURL,
            streamURLPath: streamURL.absoluteString,
            defaultQuality: nil,
            qualities: qualities,
            subtitles: subtitles
        )
    }
}

enum VideoStreamRequestError: Error, Equatable, Sendable {
    case invalidVideoId
}

extension VideoStreamRequestError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .invalidVideoId:
            return "The video identifier is invalid."
        }
    }
}
