import Foundation

@MainActor
protocol AppNotificationRouting: AnyObject {
    func route(to route: AppNotificationRoute)
}

@MainActor
final class AppNotificationRouter: AppNotificationRouting {
    private weak var appState: AppState?
    private let pendingRouteStore: PendingNotificationRouteStore
    private var lastRoute: AppNotificationRoute?
    private var lastRouteDate: Date?
    private let dedupeInterval: TimeInterval
    private let now: () -> Date

    init(
        pendingRouteStore: PendingNotificationRouteStore,
        dedupeInterval: TimeInterval = 1.5,
        now: @escaping () -> Date = Date.init
    ) {
        self.pendingRouteStore = pendingRouteStore
        self.dedupeInterval = dedupeInterval
        self.now = now
    }

    func attach(appState: AppState) {
        self.appState = appState
    }

    func route(to route: AppNotificationRoute) {
        Logger(category: "DeepLink").debug("[DeepLink] received source=remoteFCM route=\(route.logRouteName) authState=\(authStateLogValue)")
        guard route != .none else { return }

        if isSameRecentRoute(route) {
            Logger(category: "DeepLink").debug("[DeepLink] deduped route=\(route.debugDescription) reason=sameRecentRoute")
            return
        }

        guard let appState else {
            pendingRouteStore.pendingRoute = route
            remember(route)
            Logger(category: "DeepLink").debug("[DeepLink] pending reason=navigationNotReady route=\(route.debugDescription)")
            return
        }

        guard appState.launchPhase == .ready else {
            pendingRouteStore.pendingRoute = route
            remember(route)
            Logger(category: "DeepLink").debug("[DeepLink] pending reason=authRestoring route=\(route.debugDescription)")
            return
        }

        guard appState.sessionStore.isAuthenticated else {
            pendingRouteStore.pendingRoute = route
            remember(route)
            Logger(category: "DeepLink").debug("[DeepLink] pending reason=unauthenticated route=\(route.debugDescription)")
            return
        }

        guard appState.activeNotificationRoute != route,
              appState.pendingNotificationRoute != route else {
            remember(route)
            Logger(category: "DeepLink").debug("[DeepLink] skipped reason=alreadyAtDestination route=\(route.debugDescription)")
            return
        }

        remember(route)
        Logger(category: "DeepLink").info("[DeepLink] navigate route=\(route.logRouteName) \(route.logIdentifier)")
        appState.pendingNotificationRoute = route
    }

    func routePendingIfNeeded() {
        guard let route = pendingRouteStore.pendingRoute,
              let appState,
              appState.launchPhase == .ready,
              appState.sessionStore.isAuthenticated else {
            return
        }
        pendingRouteStore.pendingRoute = nil
        Logger(category: "DeepLink").info("[DeepLink] resumeAfterAuth route=\(route.debugDescription)")
        lastRoute = nil
        lastRouteDate = nil
        self.route(to: route)
    }

    private var authStateLogValue: String {
        guard let appState else { return "navigationNotReady" }
        if appState.launchPhase != .ready {
            return "restoring"
        }
        return appState.sessionStore.isAuthenticated ? "authenticated" : "unauthenticated"
    }

    private func isSameRecentRoute(_ route: AppNotificationRoute) -> Bool {
        guard let lastRoute,
              lastRoute == route,
              let lastRouteDate else {
            return false
        }
        return now().timeIntervalSince(lastRouteDate) < dedupeInterval
    }

    private func remember(_ route: AppNotificationRoute) {
        lastRoute = route
        lastRouteDate = now()
    }
}

private extension AppNotificationRoute {
    var logRouteName: String {
        switch self {
        case .orderDetail:
            return "orderDetail"
        case .orderList:
            return "orderList"
        case .chatRoom:
            return "chat"
        case .communityPost:
            return "communityPost"
        case .communityList:
            return "communityList"
        case .paymentReceipt:
            return "paymentReceipt"
        case .none:
            return "none"
        }
    }

    var logIdentifier: String {
        switch self {
        case .orderDetail(let orderCode), .paymentReceipt(let orderCode):
            return "orderCode=\(orderCode)"
        case .chatRoom(let roomId, _, _):
            return "roomId=\(roomId)"
        case .communityPost(let postId, let commentId):
            return "postId=\(postId) commentIdExists=\(commentId != nil)"
        case .orderList, .communityList, .none:
            return ""
        }
    }
}
