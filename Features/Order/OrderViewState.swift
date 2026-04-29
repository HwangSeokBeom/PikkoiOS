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
            return "결제 정보를 확인 중입니다."
        case .verified:
            return nil
        case .notVerified:
            return "결제 검증 완료 후 상태 변경이 가능합니다."
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
    let canRefreshPaymentReceipt: Bool
    let isCancelEnabled: Bool
    let isReviewWritable: Bool
    let reviewDisabledReasonText: String?
    var isPastOrder = false
    var canWriteReview = false
}

struct OrderStatusTransitionDecision: Equatable {
    let allowedNextStatus: OrderStatus?
    let isStatusChangeEnabled: Bool
    let disabledReasonText: String?
}

struct OrderStatusTransitionPolicy: Sendable {
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

        guard let nextStatus = currentStatus.allowedNextStatus else {
            return OrderStatusTransitionDecision(
                allowedNextStatus: nil,
                isStatusChangeEnabled: false,
                disabledReasonText: nil
            )
        }

        if currentStatus.requiresPaymentVerification(to: nextStatus),
           !paymentVerificationState.isVerified {
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

    func canCancel(status: OrderStatus) -> Bool {
        status.isCancellable
    }

    func reviewWritable(status: OrderStatus, reviewID: String?) -> Bool {
        status == .completed && reviewID == nil
    }

    func reviewDisabledReason(status: OrderStatus, reviewID: String?) -> String? {
        if reviewID != nil {
            return "이미 이 주문에 대한 리뷰를 작성했어요."
        }
        return status == .completed ? nil : "픽업완료 후 리뷰를 작성할 수 있어요."
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
