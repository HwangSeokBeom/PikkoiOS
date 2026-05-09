import Foundation

struct OrderViewState: Equatable {
    var title = "주문 내역"
    var subtitle = "픽업 진행 상황과 최근 주문을 한눈에 확인해 보세요."
    var orders: [OrderListItemViewState] = []
    var selectedFilter: OrderListFilter = .all
    var highlightedOrderID: String?
    var isInitialLoading = false
    var isRefreshing = false
    var isLoadingMore = false
    var canLoadMore = false
    var nextCursor: String?
    var errorMessage: String?
    var successMessage: String?
    var hiddenOrderUndoCode: String?
    var emptyState: OrderEmptyState?
    var requiresAuthentication = false
    var cancellingOrderIDs: Set<String> = []
    var statusUpdatingOrderCodes: Set<String> = []
}

enum PaymentVerificationState: Equatable, Sendable {
    case unchecked
    case checking
    case verified
    case notVerified
    case failed(String)

    var isVerified: Bool {
        if case .verified = self {
            return true
        }
        return false
    }

    var statusMessage: String? {
        switch self {
        case .unchecked, .checking:
            return "결제 정보 확인 후 상태를 변경할 수 있어요."
        case .verified:
            return nil
        case .notVerified:
            return "결제 완료 확인 후 상태를 변경할 수 있어요."
        case .failed(let message):
            return message.isEmpty ? "결제 정보를 확인할 수 없습니다." : message
        }
    }

    var shouldShowRefreshAction: Bool {
        switch self {
        case .verified, .checking:
            return false
        case .unchecked, .notVerified, .failed:
            return true
        }
    }
}

struct OrderListItemViewState: Equatable, Identifiable {
    let id: String
    let orderCode: String
    let storeName: String
    let storeImagePath: String?
    let status: OrderStatus
    let statusTitle: String
    let currentStatus: OrderStatus
    let currentStatusTitle: String
    let statusSteps: [OrderProgressStepViewState]
    let primaryItemText: String
    let itemRows: [OrderMenuItemViewState]
    let itemCountText: String
    let createdAtText: String
    let pickupTimeText: String?
    let totalPriceText: String
    let reviewRatingText: String?
    let isHighlighted: Bool
    let canCancel: Bool
    let isCancelling: Bool
    let isStatusUpdating: Bool
    let paymentVerificationState: PaymentVerificationState
    let isPaymentVerified: Bool
    let isPaymentCompleted: Bool
    let allowedNextStatus: OrderStatus?
    let allowedNextStatusTitle: String?
    let isStatusChangeEnabled: Bool
    let statusChangeMessage: String?
    let disabledReasonText: String?
    let cancelDisabledReasonText: String?
    let canRefreshPaymentReceipt: Bool
    let isCancelEnabled: Bool
    let isReviewWritable: Bool
    let reviewDisabledReasonText: String?
    let canHideFromHistory: Bool
    var isPastOrder = false
    var canWriteReview = false
}

struct OrderStatusTransitionDecision: Equatable {
    let allowedNextStatus: OrderStatus?
    let isStatusChangeEnabled: Bool
    let disabledReasonText: String?
}

struct OrderStatusTransitionResolver: Sendable {
    func decision(
        currentStatus: OrderStatus,
        paymentVerificationState: PaymentVerificationState
    ) -> OrderStatusTransitionDecision {
        guard currentStatus.canEvaluateStatusTransition else {
            return OrderStatusTransitionDecision(
                allowedNextStatus: nil,
                isStatusChangeEnabled: false,
                disabledReasonText: "주문 상태를 확인할 수 없어 최신 주문 정보가 필요합니다."
            )
        }

        guard let nextStatus = sequentialNextStatus(after: currentStatus) else {
            return OrderStatusTransitionDecision(
                allowedNextStatus: nil,
                isStatusChangeEnabled: false,
                disabledReasonText: nil
            )
        }

        if !paymentVerificationState.isVerified {
            return OrderStatusTransitionDecision(
                allowedNextStatus: nil,
                isStatusChangeEnabled: false,
                disabledReasonText: paymentVerificationState.statusMessage
            )
        }

        return OrderStatusTransitionDecision(
            allowedNextStatus: nextStatus,
            isStatusChangeEnabled: true,
            disabledReasonText: nil
        )
    }

    func allowedNextStatus(
        currentStatus: OrderStatus,
        paymentVerificationState: PaymentVerificationState
    ) -> OrderStatus? {
        decision(
            currentStatus: currentStatus,
            paymentVerificationState: paymentVerificationState
        ).allowedNextStatus
    }

    func canTransition(
        currentStatus: OrderStatus,
        nextStatus: OrderStatus,
        paymentVerificationState: PaymentVerificationState
    ) -> Bool {
        allowedNextStatus(
            currentStatus: currentStatus,
            paymentVerificationState: paymentVerificationState
        ) == nextStatus
    }

    private func sequentialNextStatus(after status: OrderStatus) -> OrderStatus? {
        switch status {
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

    func canCancel(status: OrderStatus, paymentVerificationState: PaymentVerificationState) -> Bool {
        status.isCancellable && paymentVerificationState.isVerified
    }
}

enum OrderCancelStrategy: String, Equatable, Sendable {
    case serverOrderCancel
    case serverPaymentCancel
    case localPendingCancel
    case unsupported
}

enum OrderCancelPolicyReason: String, Equatable, Sendable {
    case available
    case localPendingCancelAvailable
    case cancelEndpointUnavailable
    case missingPaymentIdentifier
    case approvedAfterCannotCancel
    case terminalStatus
    case unsupportedStatus
}

struct OrderCancelPolicy: Equatable, Sendable {
    let canShowCancelButton: Bool
    let canExecuteCancel: Bool
    let strategy: OrderCancelStrategy
    let reason: OrderCancelPolicyReason
    let userMessage: String?
    let debugReason: String
    let hasPaymentIdentifier: Bool
    let cancelEndpointAvailable: Bool
}

struct OrderCancelPolicyResolver: Sendable {
    // Swagger currently exposes no order cancel, payment cancel, or refund endpoint.
    private let orderCancelEndpointAvailable = false
    private let paymentCancelEndpointAvailable = false

    func policy(
        rawStatus: OrderStatus,
        mappedStatus: OrderStatus,
        paid: Bool,
        paymentLookupKey: String?,
        paymentID: String?,
        merchantUID: String?,
        impUID: String?
    ) -> OrderCancelPolicy {
        let hasPaymentIdentifier = [
            paymentLookupKey,
            paymentID,
            merchantUID,
            impUID
        ].contains { value in
            value?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        }

        if rawStatus == .cancelled || mappedStatus.isTerminal {
            return OrderCancelPolicy(
                canShowCancelButton: false,
                canExecuteCancel: false,
                strategy: .unsupported,
                reason: .terminalStatus,
                userMessage: nil,
                debugReason: "terminalStatus",
                hasPaymentIdentifier: hasPaymentIdentifier,
                cancelEndpointAvailable: false
            )
        }

        guard rawStatus == .pending || mappedStatus == .pending else {
            return OrderCancelPolicy(
                canShowCancelButton: false,
                canExecuteCancel: false,
                strategy: .unsupported,
                reason: .approvedAfterCannotCancel,
                userMessage: "매장 승인 후에는 앱에서 취소할 수 없어요.",
                debugReason: "approvedAfterCannotCancel",
                hasPaymentIdentifier: hasPaymentIdentifier,
                cancelEndpointAvailable: false
            )
        }

        if orderCancelEndpointAvailable {
            return OrderCancelPolicy(
                canShowCancelButton: true,
                canExecuteCancel: true,
                strategy: .serverOrderCancel,
                reason: .available,
                userMessage: "주문을 잘못했다면 매장 승인 전까지 취소할 수 있어요.",
                debugReason: "serverOrderCancelEndpointAvailable",
                hasPaymentIdentifier: hasPaymentIdentifier,
                cancelEndpointAvailable: orderCancelEndpointAvailable
            )
        }

        if hasPaymentIdentifier || paid {
            guard paymentCancelEndpointAvailable else {
                return OrderCancelPolicy(
                    canShowCancelButton: true,
                    canExecuteCancel: false,
                    strategy: .unsupported,
                    reason: .cancelEndpointUnavailable,
                    userMessage: "결제 취소 API가 필요해요. 매장에 문의해 주세요.",
                    debugReason: "paymentIdentifierPresentButNoPaymentCancelEndpoint",
                    hasPaymentIdentifier: hasPaymentIdentifier,
                    cancelEndpointAvailable: false
                )
            }

            return OrderCancelPolicy(
                canShowCancelButton: true,
                canExecuteCancel: hasPaymentIdentifier,
                strategy: .serverPaymentCancel,
                reason: hasPaymentIdentifier ? .available : .missingPaymentIdentifier,
                userMessage: hasPaymentIdentifier
                    ? "주문을 잘못했다면 매장 승인 전까지 취소할 수 있어요."
                    : "결제 정보를 확인할 수 없어 앱에서 취소할 수 없어요.",
                debugReason: hasPaymentIdentifier ? "serverPaymentCancelEndpointAvailable" : "missingPaymentIdentifier",
                hasPaymentIdentifier: hasPaymentIdentifier,
                cancelEndpointAvailable: true
            )
        }

        return OrderCancelPolicy(
            canShowCancelButton: true,
            canExecuteCancel: true,
            strategy: .localPendingCancel,
            reason: .localPendingCancelAvailable,
            userMessage: "결제 정보를 확인하고 있어요. 주문을 잘못했다면 취소할 수 있어요.",
            debugReason: "pendingApprovalUnpaidNoPaymentIdentifierNoServerCancelEndpoint",
            hasPaymentIdentifier: false,
            cancelEndpointAvailable: false
        )
    }
}

struct OrderReviewEligibilityDecision: Equatable {
    let alreadyReviewed: Bool
    let matchedReviewID: String?
    let isWritable: Bool
    let reason: String
    let disabledReasonText: String?
}

struct OrderReviewEligibilityResolver: Sendable {
    func decision(
        storeID: String,
        status: OrderStatus,
        paymentVerificationState: PaymentVerificationState,
        reviewID: String?
    ) -> OrderReviewEligibilityDecision {
        let normalizedStoreID = storeID.trimmingCharacters(in: .whitespacesAndNewlines)
        let alreadyReviewed = reviewID != nil

        if normalizedStoreID.isEmpty {
            return OrderReviewEligibilityDecision(
                alreadyReviewed: alreadyReviewed,
                matchedReviewID: reviewID,
                isWritable: false,
                reason: "missingStoreId",
                disabledReasonText: "가게 정보를 확인한 뒤 리뷰를 작성할 수 있어요."
            )
        }

        guard status == .completed else {
            return OrderReviewEligibilityDecision(
                alreadyReviewed: alreadyReviewed,
                matchedReviewID: reviewID,
                isWritable: false,
                reason: "notPickedUp",
                disabledReasonText: "픽업완료 후 리뷰를 작성할 수 있어요."
            )
        }

        if alreadyReviewed {
            return OrderReviewEligibilityDecision(
                alreadyReviewed: true,
                matchedReviewID: reviewID,
                isWritable: false,
                reason: "alreadyReviewed",
                disabledReasonText: "이미 이 주문에 대한 리뷰를 작성했어요."
            )
        }

        _ = paymentVerificationState
        return OrderReviewEligibilityDecision(
            alreadyReviewed: false,
            matchedReviewID: nil,
            isWritable: true,
            reason: "pickedUpAndNotReviewed",
            disabledReasonText: nil
        )
    }
}

struct OrderProgressStepViewState: Equatable, Identifiable {
    enum State: Equatable {
        case completed
        case current
        case pending
        case exception
    }

    let id: String
    let title: String
    let timeText: String?
    let state: State
}

struct OrderMenuItemViewState: Equatable, Identifiable {
    let id: String
    let name: String
    let quantityText: String
    let priceText: String
    let imagePath: String?
}
