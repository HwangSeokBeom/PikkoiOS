import Foundation

struct OrderDetailViewState: Equatable {
    var title = "주문 상세"
    var orderID: String
    var orderCode = ""
    var storeID: String?
    var storeName = ""
    var reviewID: String?
    var storeCategoryText: String?
    var storeCloseText: String?
    var storeImagePath: String?
    var statusTitle = ""
    var createdAtText = ""
    var paidAtText: String?
    var pickupTimeText: String?
    var totalPriceText = ""
    var paymentStatusText: String?
    var paymentMethodText: String?
    var memoText: String?
    var orderStatus: OrderStatus?
    var items: [OrderDetailItemViewState] = []
    var timelineStages: [OrderStatusTimelineView.Stage] = []
    var isLoading = false
    var isCancelling = false
    var hasLoadedContent = false
    var emptyState: OrderEmptyState?
    var errorMessage: String?
    var cancelErrorMessage: String?
    var cancelSuccessMessage: String?
    var reviewActionTitle: String?
    var isReviewActionEnabled = false
    var canCancelOrder = false
    var canExecuteCancelOrder = false
    var cancelDisabledReasonText: String?
    var paymentBridgeContext: CheckoutPaymentBridgeContext?
    var isPaymentRecoveryCandidate = false
    var paymentRecoveryTitle: String?
    var paymentRecoveryMessage: String?
    var paymentRecoveryPrimaryActionTitle: String?
    var paymentRecoverySecondaryActionTitle: String?
    var isPaymentRecoveryInProgress = false
}

struct OrderDetailItemViewState: Equatable, Identifiable {
    let id: String
    let name: String
    let quantityText: String
    let priceText: String
    let imagePath: String?
}
