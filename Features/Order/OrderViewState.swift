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

struct OrderListItemViewState: Equatable, Identifiable {
    let id: String
    let orderCode: String
    let storeName: String
    let storeImagePath: String?
    let status: OrderStatus
    let statusTitle: String
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
    let isPaymentCompleted: Bool
    let allowedNextStatus: OrderStatus?
    let statusChangeMessage: String?
    var isPastOrder = false
    var canWriteReview = false
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
