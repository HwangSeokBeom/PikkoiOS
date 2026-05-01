import Foundation

@MainActor
protocol AppNotificationRepository {
    func fetchNotifications() -> [AppNotification]
    func saveNotification(_ notification: AppNotification) -> AppNotificationSaveResult
    func saveNotifications(_ notifications: [AppNotification]) -> [AppNotificationSaveResult]
    func markAsRead(id: String)
    func markAllAsRead()
    func deleteNotification(id: String)
    func deleteAll()
    func unreadCount() -> Int
}
