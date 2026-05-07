import Foundation

struct VideoCardModel: Identifiable, Equatable {
    let id: String
    let video: Video
    let title: String
    let description: String
    let thumbnailURL: String?
    let durationText: String
    let viewCountText: String
    let likeCountText: String
    let isLiked: Bool
    let qualityLabels: [String]
    let createdAtText: String
    let isLikeUpdating: Bool
}

struct VideoListViewState: Equatable {
    var videos: [VideoCardModel] = []
    var nextCursor: String?
    var isLoading = true
    var isRefreshing = false
    var isPaging = false
    var errorMessage: String?
    var activeShortsVideoID: String?
    var isShortsPlaying = false

    var showsEmptyState: Bool {
        !isLoading && errorMessage == nil && videos.isEmpty
    }

    var showsErrorState: Bool {
        !isLoading && videos.isEmpty && errorMessage != nil
    }
}
