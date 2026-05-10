import Foundation

enum OrderListFilter: String, CaseIterable, Equatable, Sendable, Identifiable {
    case all
    case active
    case completed
    case cancelled

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all:
            return "전체"
        case .active:
            return "진행 중"
        case .completed:
            return "완료"
        case .cancelled:
            return "취소"
        }
    }

    func includes(status: OrderStatus) -> Bool {
        switch self {
        case .all:
            return true
        case .active:
            return !status.isTerminal
        case .completed:
            return status == .completed
        case .cancelled:
            return status == .cancelled || status == .failed
        }
    }
}

enum OrderFeatureError: Error, Equatable {
    case authenticationRequired
    case notFound
    case configurationRequired
    case alreadyValidated
    case unavailable(message: String)

    var userMessage: String {
        switch self {
        case .authenticationRequired:
            return "로그인 후 주문 내역을 확인할 수 있어요."
        case .notFound:
            return "주문 정보를 찾을 수 없어요."
        case .configurationRequired:
            return "앱 설정을 확인해 주세요."
        case .alreadyValidated:
            return "이미 확인된 결제예요. 주문 내역을 새로고침해 주세요."
        case .unavailable(let message):
            return message
        }
    }
}

struct OrderEmptyState: Equatable {
    let title: String
    let message: String
    let actionTitle: String
    let requiresAuthentication: Bool
}

struct OrderStatusChangeNotification: Sendable {
    let orderID: String?
    let orderCode: String
    let status: OrderStatus
}

struct OrderRefreshNotification: Sendable {
    let orderID: String?
    let orderCode: String?
    let message: String?
}

extension Notification.Name {
    static let pikkoOrderStatusDidChange = Notification.Name("pikko.order.statusDidChange")
    static let pikkoOrdersShouldRefresh = Notification.Name("pikko.orders.shouldRefresh")
}

enum OrderStatusChangeNotificationUserInfoKey {
    static let event = "event"
}

enum OrderRefreshNotificationUserInfoKey {
    static let event = "event"
}
