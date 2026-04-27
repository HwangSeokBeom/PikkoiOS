import Foundation

enum OrderStatus: Equatable, Sendable {
    case pending
    case accepted
    case preparing
    case ready
    case completed
    case cancelled
    case failed
    case unknown(String)

    init(serverValue: String) {
        switch serverValue.uppercased() {
        case "PENDING_APPROVAL":
            self = .pending
        case "APPROVED":
            self = .accepted
        case "IN_PROGRESS":
            self = .preparing
        case "READY_FOR_PICKUP":
            self = .ready
        case "PICKED_UP":
            self = .completed
        case "CANCELLED":
            self = .cancelled
        case "FAILED":
            self = .failed
        default:
            self = .unknown(serverValue)
        }
    }

    var displayTitle: String {
        switch self {
        case .pending:
            return "승인 대기"
        case .accepted:
            return "주문 승인"
        case .preparing:
            return "준비 중"
        case .ready:
            return "픽업 대기"
        case .completed:
            return "픽업 완료"
        case .cancelled:
            return "주문 취소"
        case .failed:
            return "주문 실패"
        case .unknown:
            return "상태 확인 중"
        }
    }

    var isTerminal: Bool {
        switch self {
        case .completed, .cancelled, .failed:
            return true
        case .pending, .accepted, .preparing, .ready, .unknown:
            return false
        }
    }

    var isCancellable: Bool {
        self == .pending
    }
}

struct OrderSummary: Equatable, Sendable, Identifiable {
    let id: String
    let orderCode: String
    let storeID: String
    let storeName: String
    let storeImagePath: String?
    let status: OrderStatus
    let createdAt: Date
    let totalAmount: Decimal
    let itemSummaries: [OrderItemSummary]
    let pickupTime: Date?

    var canCancel: Bool {
        status.isCancellable
    }
}

struct OrderItemSummary: Equatable, Sendable, Identifiable {
    let id: String
    let menuName: String
    let quantity: Int
    let imagePath: String?
    let unitPriceAmount: Decimal?
}

struct OrderPaymentSummary: Equatable, Sendable {
    let statusText: String?
    let methodText: String?
    let paidAt: Date?
    let receiptURL: URL?
}

struct OrderStatusTimelineEntry: Equatable, Sendable, Identifiable {
    let id: String
    let status: OrderStatus
    let completed: Bool
    let changedAt: Date?
}
