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

    var canEvaluateStatusTransition: Bool {
        if case .unknown = self {
            return false
        }
        return true
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
        case .pending:
            return true
        case .accepted, .preparing, .ready, .completed, .cancelled, .rejected, .failed, .unknown:
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

    var isPaymentCompletionEvidence: Bool {
        switch self {
        case .accepted, .preparing, .ready, .completed:
            return true
        case .pending, .cancelled, .rejected, .failed, .unknown:
            return false
        }
    }
}

struct OrderPaymentCompletionEvidence: Equatable, Sendable {
    let isCompleted: Bool
    let source: String
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
        status.isCancellable && isPaymentCompleted
    }

    var isPaymentCompleted: Bool {
        paymentCompletionEvidence.isCompleted
    }

    var paymentEvidenceSource: String {
        paymentCompletionEvidence.source
    }

    var isRecoverablePendingPayment: Bool {
        status == .pending
            && paidAt == nil
            && !isPaymentCompleted
            && paymentEvidenceSource == "none"
            && !orderCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && totalAmount > 0
            && !itemSummaries.isEmpty
    }

    var paymentRecoveryDisplayName: String {
        let firstName = itemSummaries.first?.menuName.trimmingCharacters(in: .whitespacesAndNewlines)
        let baseName = firstName?.isEmpty == false ? firstName! : storeName
        let distinctCount = itemSummaries.count
        return distinctCount > 1 ? "\(baseName) 외 \(distinctCount - 1)개" : baseName
    }

    var paymentCompletionEvidence: OrderPaymentCompletionEvidence {
        let normalizedVerificationState = paymentVerificationState.normalizedPaymentState
        if normalizedVerificationState == "verified" {
            return OrderPaymentCompletionEvidence(isCompleted: true, source: "paymentVerificationState")
        }
        if ["notverified", "not_verified", "failed", "failure"].contains(normalizedVerificationState) {
            return OrderPaymentCompletionEvidence(isCompleted: false, source: "paymentVerificationState")
        }

        let normalizedPaymentStatus = paymentStatus.normalizedPaymentState
        if ["paid", "completed", "complete", "succeeded", "success", "approved"].contains(normalizedPaymentStatus) {
            return OrderPaymentCompletionEvidence(isCompleted: true, source: "paymentStatus")
        }
        if ["cancelled", "canceled", "failed", "failure", "ready", "pending"].contains(normalizedPaymentStatus) {
            return OrderPaymentCompletionEvidence(isCompleted: false, source: "paymentStatus")
        }

        if paidAt != nil {
            return OrderPaymentCompletionEvidence(isCompleted: true, source: "paidAt")
        }
        if receiptExists || receiptURL != nil {
            return OrderPaymentCompletionEvidence(isCompleted: true, source: "receipt")
        }
        if status.isPaymentCompletionEvidence {
            return OrderPaymentCompletionEvidence(isCompleted: true, source: "orderStatus")
        }
        return OrderPaymentCompletionEvidence(isCompleted: false, source: hasPaymentLookupEvidence ? "paymentLookup" : "none")
    }

    private var hasPaymentLookupEvidence: Bool {
        [
            paymentLookupKey,
            paymentID,
            merchantUID,
            impUID
        ].contains { value in
            value?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        }
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

extension OrderDetail {
    var isRecoverablePendingPayment: Bool {
        let normalizedPaymentStatus = paymentSummary?.statusText?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "-", with: "_")
            ?? ""
        let hasPaidSummary = paymentSummary?.paidAt != nil
            || paymentSummary?.receiptURL != nil
            || ["paid", "completed", "complete", "succeeded", "success", "approved"].contains(normalizedPaymentStatus)

        return status == .pending
            && paidAt == nil
            && !hasPaidSummary
            && !orderCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && totalAmount > 0
            && !items.isEmpty
    }

    var paymentRecoveryDisplayName: String {
        let firstName = items.first?.menuName.trimmingCharacters(in: .whitespacesAndNewlines)
        let baseName = firstName?.isEmpty == false ? firstName! : storeName
        let distinctCount = items.count
        return distinctCount > 1 ? "\(baseName) 외 \(distinctCount - 1)개" : baseName
    }
}

private extension Optional where Wrapped == String {
    var normalizedPaymentState: String {
        self?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "-", with: "_")
            ?? ""
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
