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

    var apiValue: String {
        switch self {
        case .pending:
            return "PENDING_APPROVAL"
        case .accepted:
            return "APPROVED"
        case .preparing:
            return "IN_PROGRESS"
        case .ready:
            return "READY_FOR_PICKUP"
        case .completed:
            return "PICKED_UP"
        case .cancelled:
            return "CANCELLED"
        case .rejected:
            return "REJECTED"
        case .failed:
            return "FAILED"
        case .unknown(let value):
            return value
        }
    }

    var sortOrder: Int {
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
        case .cancelled:
            return 5
        case .rejected:
            return 6
        case .failed:
            return 7
        case .unknown:
            return 8
        }
    }

    static var selectableStatuses: [OrderStatus] {
        [.pending, .accepted, .preparing, .ready, .completed]
    }

    var allowedNextStatus: OrderStatus? {
        switch self {
        case .pending:
            return .accepted
        case .accepted:
            return .preparing
        case .preparing:
            return .ready
        case .ready:
            return .completed
        case .completed, .cancelled, .rejected, .failed, .unknown:
            return nil
        }
    }

    var canEvaluateStatusTransition: Bool {
        if case .unknown = self {
            return false
        }
        return true
    }

    func canTransition(to nextStatus: OrderStatus) -> Bool {
        allowedNextStatus == nextStatus
    }

    func isEarlierProgressStep(than status: OrderStatus) -> Bool {
        guard let currentStepIndex = progressStepIndex,
              let otherStepIndex = status.progressStepIndex else {
            return false
        }
        return currentStepIndex < otherStepIndex
    }

    func requiresPaymentVerification(to nextStatus: OrderStatus) -> Bool {
        self == .pending && nextStatus == .accepted
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
        switch self {
        case .pending, .accepted:
            return true
        case .preparing, .ready, .completed, .cancelled, .rejected, .failed, .unknown:
            return false
        }
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
    let paidAt: Date?
    let totalAmount: Decimal
    let itemSummaries: [OrderItemSummary]
    let pickupTime: Date?
    let reviewID: String?
    let reviewRating: Decimal?
    let paymentLookupKey: String?
    let paymentID: String?
    let merchantUID: String?
    let impUID: String?
    let paymentStatus: String?
    let paymentVerificationState: String?
    let receiptURL: URL?
    let receiptExists: Bool

    var canCancel: Bool {
        status.isCancellable
    }

    var isPaymentCompleted: Bool {
        paidAt != nil
    }

    init(
        id: String,
        orderCode: String,
        storeID: String,
        storeName: String,
        storeImagePath: String?,
        status: OrderStatus,
        createdAt: Date,
        paidAt: Date? = nil,
        totalAmount: Decimal,
        itemSummaries: [OrderItemSummary],
        pickupTime: Date?,
        reviewID: String? = nil,
        reviewRating: Decimal? = nil,
        paymentLookupKey: String? = nil,
        paymentID: String? = nil,
        merchantUID: String? = nil,
        impUID: String? = nil,
        paymentStatus: String? = nil,
        paymentVerificationState: String? = nil,
        receiptURL: URL? = nil,
        receiptExists: Bool = false
    ) {
        self.id = id
        self.orderCode = orderCode
        self.storeID = storeID
        self.storeName = storeName
        self.storeImagePath = storeImagePath
        self.status = status
        self.createdAt = createdAt
        self.paidAt = paidAt
        self.totalAmount = totalAmount
        self.itemSummaries = itemSummaries
        self.pickupTime = pickupTime
        self.reviewID = reviewID
        self.reviewRating = reviewRating
        self.paymentLookupKey = paymentLookupKey
        self.paymentID = paymentID
        self.merchantUID = merchantUID
        self.impUID = impUID
        self.paymentStatus = paymentStatus
        self.paymentVerificationState = paymentVerificationState
        self.receiptURL = receiptURL
        self.receiptExists = receiptExists
    }

    init(
        id: String,
        orderCode: String,
        storeID: String,
        storeName: String,
        storeImagePath: String?,
        status: OrderStatus,
        createdAt: Date,
        paidAt: Date? = nil,
        totalAmount: Decimal,
        itemSummaries: [OrderItemSummary],
        pickupTime: Date?,
        reviewID: String? = nil,
        reviewRating: Decimal? = nil,
        paymentLookupKey: String? = nil,
        paymentID: String? = nil,
        merchantUID: String? = nil,
        impUID: String? = nil,
        paymentStatus: String? = nil,
        receiptURL: URL? = nil,
        receiptExists: Bool = false
    ) {
        self.init(
            id: id,
            orderCode: orderCode,
            storeID: storeID,
            storeName: storeName,
            storeImagePath: storeImagePath,
            status: status,
            createdAt: createdAt,
            paidAt: paidAt,
            totalAmount: totalAmount,
            itemSummaries: itemSummaries,
            pickupTime: pickupTime,
            reviewID: reviewID,
            reviewRating: reviewRating,
            paymentLookupKey: paymentLookupKey,
            paymentID: paymentID,
            merchantUID: merchantUID,
            impUID: impUID,
            paymentStatus: paymentStatus,
            paymentVerificationState: nil,
            receiptURL: receiptURL,
            receiptExists: receiptExists
        )
    }

    init(
        id: String,
        orderCode: String,
        storeID: String,
        storeName: String,
        storeImagePath: String?,
        status: OrderStatus,
        createdAt: Date,
        paidAt: Date? = nil,
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
            paidAt: paidAt,
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
