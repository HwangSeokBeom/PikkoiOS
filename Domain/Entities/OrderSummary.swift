import Foundation

enum OrderStatus: Equatable, Sendable {
    case pending
    case accepted
    case preparing
    case ready
    case completed
    case cancelled
    case rejected
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
        case "REJECTED", "DENIED":
            self = .rejected
        case "FAILED":
            self = .failed
        default:
            self = .unknown(serverValue)
        }
    }

    var displayTitle: String {
        switch self {
        case .pending:
            return "승인대기"
        case .accepted:
            return "주문승인"
        case .preparing:
            return "조리 중"
        case .ready:
            return "픽업대기"
        case .completed:
            return "픽업완료"
        case .cancelled:
            return "주문취소"
        case .rejected:
            return "주문거절"
        case .failed:
            return "주문실패"
        case .unknown:
            return "확인중"
        }
    }

    var isTerminal: Bool {
        switch self {
        case .completed, .cancelled, .rejected, .failed:
            return true
        case .pending, .accepted, .preparing, .ready, .unknown:
            return false
        }
    }

    var isCancellable: Bool {
        self == .pending
    }

    var progressStepIndex: Int? {
        switch self {
        case .pending:
            return 0
        case .accepted:
            return 1
        case .preparing:
            return 2
        case .ready:
            return 3
        case .completed:
            return 4
        case .cancelled, .rejected, .failed, .unknown:
            return nil
        }
    }

    var isExceptionTerminal: Bool {
        switch self {
        case .cancelled, .rejected, .failed:
            return true
        case .pending, .accepted, .preparing, .ready, .completed, .unknown:
            return false
        }
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
    let reviewID: String?
    let reviewRating: Decimal?

    var canCancel: Bool {
        status.isCancellable
    }

    init(
        id: String,
        orderCode: String,
        storeID: String,
        storeName: String,
        storeImagePath: String?,
        status: OrderStatus,
        createdAt: Date,
        totalAmount: Decimal,
        itemSummaries: [OrderItemSummary],
        pickupTime: Date?,
        reviewID: String? = nil,
        reviewRating: Decimal? = nil
    ) {
        self.id = id
        self.orderCode = orderCode
        self.storeID = storeID
        self.storeName = storeName
        self.storeImagePath = storeImagePath
        self.status = status
        self.createdAt = createdAt
        self.totalAmount = totalAmount
        self.itemSummaries = itemSummaries
        self.pickupTime = pickupTime
        self.reviewID = reviewID
        self.reviewRating = reviewRating
    }

    init(
        id: String,
        orderCode: String,
        storeID: String,
        storeName: String,
        storeImagePath: String?,
        status: OrderStatus,
        createdAt: Date,
        totalAmount: Decimal,
        itemSummaries: [OrderItemSummary],
        pickupTime: Date?
    ) {
        self.init(
            id: id,
            orderCode: orderCode,
            storeID: storeID,
            storeName: storeName,
            storeImagePath: storeImagePath,
            status: status,
            createdAt: createdAt,
            totalAmount: totalAmount,
            itemSummaries: itemSummaries,
            pickupTime: pickupTime,
            reviewID: nil,
            reviewRating: nil
        )
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
