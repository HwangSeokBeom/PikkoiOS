import Foundation

@MainActor
protocol NotificationListInteracting {
    func fetchNotifications() -> [AppNotification]
    func markAsRead(id: String)
    func markAllAsRead()
    func deleteNotification(id: String)
    func deleteAll()
}

@MainActor
struct NotificationListInteractor: NotificationListInteracting {
    private let notificationService: AppNotificationService

    init(notificationService: AppNotificationService) {
        self.notificationService = notificationService
    }

    func fetchNotifications() -> [AppNotification] {
        notificationService.fetchNotifications()
    }

    func markAsRead(id: String) {
        notificationService.markAsRead(id: id)
    }

    func markAllAsRead() {
        notificationService.markAllAsRead()
    }

    func deleteNotification(id: String) {
        notificationService.deleteNotification(id: id)
    }

    func deleteAll() {
        notificationService.deleteAll()
    }
}
