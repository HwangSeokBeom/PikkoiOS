import Foundation

struct NotificationListViewState: Equatable {
    var title = "알림"
    var items: [NotificationItemViewState] = []
    var unreadCount = 0
    var isRefreshing = false

    var emptyTitle: String? {
        items.isEmpty ? "도착한 알림이 없어요" : nil
    }

    var emptyMessage: String? {
        items.isEmpty ? "주문, 채팅, 커뮤니티 소식을 여기에서 확인할 수 있어요." : nil
    }
}

struct NotificationItemViewState: Equatable, Identifiable {
    let id: String
    let type: AppNotificationType
    let title: String
    let body: String
    let timeText: String
    let isUnread: Bool
}
