import Foundation

@MainActor
protocol NotificationListRouting: AnyObject {
    func route(to route: AppNotificationRoute)
}

@MainActor
final class NotificationListRouter: ObservableObject, NotificationListRouting {
    private let appNotificationRouter: AppNotificationRouting

    init(appNotificationRouter: AppNotificationRouting) {
        self.appNotificationRouter = appNotificationRouter
    }

    func route(to route: AppNotificationRoute) {
        appNotificationRouter.route(to: route)
    }
}
