import Foundation

@MainActor
protocol CommunityRouting: AnyObject {
    func routeToAuth(context: AuthPresentationContext, routeAfterAuth: AppRoute?)
    func routeToComposer()
    func routeToComposer(
        mode: CommunityComposerMode,
        initialDraft: CommunityComposerInitialDraft?
    )
    func routeToPostDetail(postID: String)
    func routeToStoreDetail(storeID: String)
    func routeToSearch(query: String)
    func clearPendingRoute()
}

@MainActor
final class CommunityRouter: ObservableObject, CommunityRouting {
    @Published private(set) var pendingRoute: AppRoute?
    @Published private(set) var isAuthPresented = false
    @Published private(set) var authPresentationContext: AuthPresentationContext = .generic
    private var pendingRouteAfterAuth: AppRoute?

    func routeToAuth(context: AuthPresentationContext = .generic, routeAfterAuth: AppRoute? = nil) {
        authPresentationContext = context
        pendingRouteAfterAuth = routeAfterAuth
        isAuthPresented = true
    }

    func routeToComposer() {
        pendingRoute = .communityComposer(mode: .create, initialDraft: nil)
    }

    func routeToComposer(
        mode: CommunityComposerMode,
        initialDraft: CommunityComposerInitialDraft?
    ) {
        pendingRoute = .communityComposer(mode: mode, initialDraft: initialDraft)
    }

    func routeToPostDetail(postID: String) {
        pendingRoute = .communityDetail(postID: postID)
    }

    func routeToStoreDetail(storeID: String) {
        pendingRoute = .storeDetail(storeID: storeID)
    }

    func routeToSearch(query: String) {
        pendingRoute = .communitySearch(query: query)
    }

    func clearPendingRoute() {
        pendingRoute = nil
    }

    func dismissAuth() {
        isAuthPresented = false
    }

    func completeAuthentication() {
        isAuthPresented = false
        guard let pendingRouteAfterAuth else { return }
        self.pendingRouteAfterAuth = nil
        DispatchQueue.main.async { [weak self] in
            self?.pendingRoute = pendingRouteAfterAuth
        }
    }
}
