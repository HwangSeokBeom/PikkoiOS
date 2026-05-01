import Foundation

@MainActor
protocol AppNotificationRouting: AnyObject {
    func route(to route: AppNotificationRoute)
}

@MainActor
final class AppNotificationRouter: AppNotificationRouting {
    private weak var appState: AppState?
    private let pendingRouteStore: PendingNotificationRouteStore

    init(pendingRouteStore: PendingNotificationRouteStore) {
        self.pendingRouteStore = pendingRouteStore
    }

    func attach(appState: AppState) {
        self.appState = appState
    }

    func route(to route: AppNotificationRoute) {
        Logger(category: "NotificationRoute").debug("[NotificationRoute] route requested route=\(route.debugDescription)")
        guard route != .none else { return }

        guard let appState else {
            pendingRouteStore.pendingRoute = route
            Logger(category: "NotificationRoute").debug("[NotificationRoute] pending saved route=\(route.debugDescription)")
            return
        }

        guard appState.sessionStore.isAuthenticated else {
            pendingRouteStore.pendingRoute = route
            Logger(category: "NotificationRoute").debug("[NotificationRoute] pending saved route=\(route.debugDescription)")
            return
        }

        appState.pendingNotificationRoute = route
    }

    func routePendingIfNeeded() {
        guard let route = pendingRouteStore.pendingRoute,
              let appState,
              appState.sessionStore.isAuthenticated else {
            return
        }
        pendingRouteStore.pendingRoute = nil
        Logger(category: "NotificationRoute").debug("[NotificationRoute] pending consumed route=\(route.debugDescription)")
        self.route(to: route)
    }
}
