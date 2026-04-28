import Foundation

@MainActor
protocol CommunityDetailRouting: AnyObject {
    func routeToAuth(context: AuthPresentationContext)
    func routeToComposer(
        mode: CommunityComposerMode,
        initialDraft: CommunityComposerInitialDraft?
    )
    func routeToStoreDetail(storeID: String)
    func routeToChat(target: ChatTarget)
    func requestDismiss()
    func clearPendingRoute()
}

@MainActor
final class CommunityDetailRouter: ObservableObject, CommunityDetailRouting {
    @Published private(set) var pendingRoute: AppRoute?
    @Published private(set) var isAuthPresented = false
    @Published private(set) var authPresentationContext: AuthPresentationContext = .communityComment
    @Published private(set) var dismissRequested = false

    func routeToAuth(context: AuthPresentationContext = .communityComment) {
        authPresentationContext = context
        isAuthPresented = true
    }

    func routeToComposer(
        mode: CommunityComposerMode,
        initialDraft: CommunityComposerInitialDraft?
    ) {
        pendingRoute = .communityComposer(mode: mode, initialDraft: initialDraft)
    }

    func routeToStoreDetail(storeID: String) {
        pendingRoute = .storeDetail(storeID: storeID)
    }

    func routeToChat(target: ChatTarget) {
        pendingRoute = .chat(target)
    }

    func requestDismiss() {
        dismissRequested = true
    }

    func clearPendingRoute() {
        pendingRoute = nil
    }

    func dismissAuth() {
        isAuthPresented = false
    }

    func completeAuthentication() {
        isAuthPresented = false
    }

    func clearDismissRequest() {
        dismissRequested = false
    }
}
