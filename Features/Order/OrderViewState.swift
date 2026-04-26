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
    var emptyState: OrderEmptyState?
    var requiresAuthentication = false
}

struct OrderListItemViewState: Equatable, Identifiable {
    let id: String
    let orderCode: String
    let storeName: String
    let storeImagePath: String?
    let statusTitle: String
    let primaryItemText: String
    let createdAtText: String
    let pickupTimeText: String?
    let totalPriceText: String
    let isHighlighted: Bool
}
