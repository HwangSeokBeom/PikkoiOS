import Foundation

enum NotificationListAction {
    case onAppear
    case refreshRequested
    case itemTapped(String)
    case markAllAsReadTapped
    case deleteItem(String)
    case deleteAllTapped
}

@MainActor
final class NotificationListPresenter: ObservableObject {
    @Published private(set) var viewState = NotificationListViewState()

    private let interactor: NotificationListInteracting
    private let router: NotificationListRouting
    private let relativeDateFormatter: RelativeDateTimeFormatter
    private var notifications: [AppNotification] = []

    init(interactor: NotificationListInteracting, router: NotificationListRouting) {
        self.interactor = interactor
        self.router = router
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.unitsStyle = .short
        self.relativeDateFormatter = formatter
    }

    func send(_ action: NotificationListAction) async {
        switch action {
        case .onAppear, .refreshRequested:
            reload()
        case .itemTapped(let id):
            guard let notification = notifications.first(where: { $0.id == id }) else { return }
            interactor.markAsRead(id: id)
            reload()
            if notification.route == .none {
                Logger(category: "NotificationTap").warning("[NotificationTap] routeUnavailable notificationId=\(id) reason=missingMetadata")
            } else {
                Logger(category: "NotificationTap").debug("[NotificationTap] source=notificationCenter notificationId=\(id) route=\(notification.route.debugDescription)")
            }
            router.route(to: notification.route)
        case .markAllAsReadTapped:
            interactor.markAllAsRead()
            reload()
        case .deleteItem(let id):
            interactor.deleteNotification(id: id)
            reload()
        case .deleteAllTapped:
            interactor.deleteAll()
            reload()
        }
    }

    private func reload() {
        notifications = interactor.fetchNotifications()
        viewState.items = notifications.map(makeItem)
        viewState.unreadCount = notifications.filter { $0.readState == .unread }.count
    }

    private func makeItem(_ notification: AppNotification) -> NotificationItemViewState {
        NotificationItemViewState(
            id: notification.id,
            type: notification.type,
            title: notification.title,
            body: notification.body,
            timeText: relativeDateFormatter.localizedString(for: notification.createdAt, relativeTo: Date()),
            isUnread: notification.readState == .unread
        )
    }
}
