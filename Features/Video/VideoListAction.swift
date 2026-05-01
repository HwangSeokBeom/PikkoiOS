import Foundation

enum VideoListAction {
    case onAppear
    case refreshRequested
    case retryTapped
    case videoAppeared(String)
    case videoTapped(String)
    case videoLikeTapped(String)
    case videoUpdated(Video)
}
