import Foundation

@MainActor
protocol CommunityComposerRouting: AnyObject {
    func routeToPostDetail(postID: String)
    func clearPendingRoute()
}

@MainActor
final class CommunityComposerRouter: ObservableObject, CommunityComposerRouting {
    @Published private(set) var pendingRoute: AppRoute?

    func routeToPostDetail(postID: String) {
        pendingRoute = .communityDetail(postID: postID)
    }

    func clearPendingRoute() {
        pendingRoute = nil
    }
}
