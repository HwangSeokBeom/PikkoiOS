import Foundation

enum VideoListViewDisappearReason: String, Equatable {
    case tabSwitch
    case openOriginal
    case appBackground
    case pop
    case deinitializing
}

enum VideoListAction {
    case onAppear
    case refreshRequested
    case retryTapped
    case videoAppeared(String)
    case visibleVideoChanged(String)
    case videoTapped(String)
    case originalVideoTapped(String)
    case originalRouteCleared
    case videoLikeTapped(String)
    case videoUpdated(Video)
    case viewDisappeared(reason: VideoListViewDisappearReason)
    case scenePhaseChanged(isActive: Bool)
    case visibilityChanged(isVisible: Bool, reason: VideoListViewDisappearReason)
    case shortsPlaybackSnapshotUpdated(VideoLiveActivitySnapshot)
}
