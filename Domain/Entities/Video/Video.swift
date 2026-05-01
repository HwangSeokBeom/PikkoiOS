import Foundation

struct Video: Equatable, Sendable, Identifiable {
    var id: String { videoId }

    let videoId: String
    let fileName: String
    let title: String
    let description: String
    let duration: Double
    let thumbnailURL: String?
    let availableQualities: [String]
    let viewCount: Int
    let likeCount: Int
    let isLiked: Bool
    let createdAt: Date?
}

extension Video {
    func updatingLikeStatus(_ isLiked: Bool) -> Video {
        let delta: Int
        switch (self.isLiked, isLiked) {
        case (true, false):
            delta = -1
        case (false, true):
            delta = 1
        default:
            delta = 0
        }

        return Video(
            videoId: videoId,
            fileName: fileName,
            title: title,
            description: description,
            duration: duration,
            thumbnailURL: thumbnailURL,
            availableQualities: availableQualities,
            viewCount: viewCount,
            likeCount: max(likeCount + delta, 0),
            isLiked: isLiked,
            createdAt: createdAt
        )
    }
}
