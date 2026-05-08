import Foundation

@MainActor
final class AppState: ObservableObject {
    @Published var launchPhase: LaunchPhase = .idle {
        willSet { MainActorStateAssertions.assertMainThreadForUIStateMutation(context: "AppState.launchPhase") }
    }
    @Published var selectedTab: RootTab = .home {
        willSet { MainActorStateAssertions.assertMainThreadForUIStateMutation(context: "AppState.selectedTab") }
    }
    @Published var pendingDeepLink: URL? {
        willSet { MainActorStateAssertions.assertMainThreadForUIStateMutation(context: "AppState.pendingDeepLink") }
    }
    @Published var pendingHighlightedOrderID: String? {
        willSet { MainActorStateAssertions.assertMainThreadForUIStateMutation(context: "AppState.pendingHighlightedOrderID") }
    }
    @Published var pendingNotificationRoute: AppNotificationRoute? {
        willSet { MainActorStateAssertions.assertMainThreadForUIStateMutation(context: "AppState.pendingNotificationRoute") }
    }
    @Published var pendingNotificationRouteSource: NotificationRouteSource? {
        willSet { MainActorStateAssertions.assertMainThreadForUIStateMutation(context: "AppState.pendingNotificationRouteSource") }
    }
    @Published var activeNotificationRoute: AppNotificationRoute? {
        willSet { MainActorStateAssertions.assertMainThreadForUIStateMutation(context: "AppState.activeNotificationRoute") }
    }
    @Published var activeNotificationRouteSource: NotificationRouteSource? {
        willSet { MainActorStateAssertions.assertMainThreadForUIStateMutation(context: "AppState.activeNotificationRouteSource") }
    }
    @Published var globalToast: GlobalToast? {
        willSet { MainActorStateAssertions.assertMainThreadForUIStateMutation(context: "AppState.globalToast") }
    }

    let sessionStore: SessionStore
    let cartStore: CartStore

    init(sessionStore: SessionStore, cartStore: CartStore) {
        self.sessionStore = sessionStore
        self.cartStore = cartStore
    }

    var shouldPresentAuthGate: Bool {
        !sessionStore.isAuthenticated
    }
}
