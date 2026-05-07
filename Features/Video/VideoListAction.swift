import Foundation

enum VideoListAction {
    case onAppear
    case refreshRequested
    case retryTapped
    case videoAppeared(String)
    case visibleVideoChanged(String)
    case videoTapped(String)
    case originalVideoTapped(String)
    case videoLikeTapped(String)
    case videoUpdated(Video)
    case viewDisappeared
    case scenePhaseChanged(isActive: Bool)
}
