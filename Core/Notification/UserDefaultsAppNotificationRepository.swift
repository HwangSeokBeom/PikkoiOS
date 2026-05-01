import Foundation

@MainActor
final class UserDefaultsAppNotificationRepository: AppNotificationRepository {
    private enum StorageKey {
        static let notifications = "appNotifications.items"
    }

    private let store: any UserDefaultsStoring
    private let maximumStoredCount: Int

    init(store: any UserDefaultsStoring, maximumStoredCount: Int = 200) {
        self.store = store
        self.maximumStoredCount = maximumStoredCount
    }

    func fetchNotifications() -> [AppNotification] {
        load()
    }

    func saveNotification(_ notification: AppNotification) -> AppNotificationSaveResult {
        saveNotifications([notification]).first ?? .failed(reason: "emptySaveResult")
    }

    func saveNotifications(_ notifications: [AppNotification]) -> [AppNotificationSaveResult] {
        guard !notifications.isEmpty else { return [] }

        var items = load()
        var existingIDs = Set(items.map(\.id))
        var pendingNotifications: [AppNotification] = []
        var results: [AppNotificationSaveResult] = []

        for notification in notifications {
            guard !existingIDs.contains(notification.id) else {
                results.append(.duplicate(id: notification.id))
                continue
            }
            items.append(notification)
            existingIDs.insert(notification.id)
            pendingNotifications.append(notification)
            results.append(.saved(unreadCount: 0))
        }

        guard !pendingNotifications.isEmpty else {
            return results
        }

        guard persist(items) else {
            return notifications.map { .failed(reason: "persistFailed id=\($0.id)") }
        }

        let unreadCount = self.unreadCount()
        return results.map { result in
            switch result {
            case .saved:
                return .saved(unreadCount: unreadCount)
            default:
                return result
            }
        }
    }

    func markAsRead(id: String) {
        var items = load()
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].readState = .read
        persist(items)
    }

    func markAllAsRead() {
        let items = load().map { notification in
            var copy = notification
            copy.readState = .read
            return copy
        }
        persist(items)
    }

    func deleteNotification(id: String) {
        persist(load().filter { $0.id != id })
    }

    func deleteAll() {
        store.removeValue(forKey: StorageKey.notifications)
    }

    func unreadCount() -> Int {
        load().filter { $0.readState == .unread }.count
    }

    private func load() -> [AppNotification] {
        let notifications = store.codableValue([AppNotification].self, forKey: StorageKey.notifications) ?? []
        return sortedAndTrimmed(notifications)
    }

    @discardableResult
    private func persist(_ notifications: [AppNotification]) -> Bool {
        let normalized = sortedAndTrimmed(notifications)
        do {
            try store.setCodable(normalized, forKey: StorageKey.notifications)
            return true
        } catch {
            Logger(category: "Notification").warning("[Notification] persist failed error=\(error.localizedDescription)")
            return false
        }
    }

    private func sortedAndTrimmed(_ notifications: [AppNotification]) -> [AppNotification] {
        Array(
            notifications
                .sorted { lhs, rhs in
                    if lhs.createdAt == rhs.createdAt {
                        return lhs.id > rhs.id
                    }
                    return lhs.createdAt > rhs.createdAt
                }
                .prefix(maximumStoredCount)
        )
    }
}
