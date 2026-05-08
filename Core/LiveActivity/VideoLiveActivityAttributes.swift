import Foundation

#if canImport(ActivityKit)
import ActivityKit

struct VideoLiveActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        let playbackState: String
        let elapsedTime: Double
        let duration: Double
        let quality: String
        let hasArtwork: Bool
        let updatedAt: Date
    }

    let videoId: String
    let title: String
    let thumbnailURLString: String?
}
#endif

