import Foundation

@MainActor
final class AppState: ObservableObject {
    @Published var launchPhase: LaunchPhase = .idle
    @Published var selectedTab: RootTab = .home
    @Published var pendingDeepLink: URL?
    @Published var pendingHighlightedOrderID: String?
    @Published var pendingNotificationRoute: AppNotificationRoute?
    @Published var pendingNotificationRouteSource: NotificationRouteSource?
    @Published var activeNotificationRoute: AppNotificationRoute?
    @Published var activeNotificationRouteSource: NotificationRouteSource?
    @Published var globalToast: GlobalToast?

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
