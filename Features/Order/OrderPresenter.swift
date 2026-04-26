import Foundation

@MainActor
final class OrderPresenter: ObservableObject {
    @Published private(set) var viewState = OrderViewState()

    private let interactor: OrderInteracting
    private let router: OrderRouting
    private let currencyFormatter = CurrencyFormatter()
    private let dateParser = DateParser()

    private var hasLoaded = false
    private var isRequestInFlight = false
    private var hasAutoNavigatedHighlightedOrder = false
    private var allOrders: [OrderSummary] = []

    init(interactor: OrderInteracting, router: OrderRouting) {
        self.interactor = interactor
        self.router = router
    }

    func send(_ action: OrderAction) async {
        switch action {
        case .onAppear:
            guard !hasLoaded else { return }
            hasLoaded = true
            viewState = await interactor.loadInitialState()
            guard viewState.isInitialLoading else { return }
            await loadOrders(mode: .initial)

        case .refreshRequested:
            await loadOrders(mode: .refresh)

        case .retryTapped:
            await loadOrders(mode: viewState.orders.isEmpty ? .initial : .refresh)

        case .filterTapped(let filter):
            guard viewState.selectedFilter != filter else { return }
            viewState.selectedFilter = filter
            applyOrders(resetErrorMessage: false)
            await attemptAutoNavigationIfNeeded()

        case .orderTapped(let orderID):
            router.routeToOrderDetail(orderID: orderID)

        case .orderAppeared(let orderID):
            guard orderID == viewState.orders.last?.id,
                  viewState.canLoadMore,
                  !viewState.isLoadingMore,
                  !isRequestInFlight else { return }
            await loadOrders(mode: .loadMore)

        case .loginRequiredTapped:
            router.routeToAuth()

        case .exploreStoresTapped:
            router.routeToExploreHome()
        }
    }

    private func loadOrders(mode: LoadingMode) async {
        guard !isRequestInFlight else { return }
        isRequestInFlight = true
        setLoadingFlags(for: mode, isLoading: true)
        if mode != .loadMore {
            viewState.errorMessage = nil
        }

        do {
            let page = try await interactor.fetchOrders(
                cursor: mode == .loadMore ? viewState.nextCursor : nil,
                filter: viewState.selectedFilter
            )
            merge(page: page, mode: mode)
            applyOrders(resetErrorMessage: true)
            await attemptAutoNavigationIfNeeded()
        } catch {
            apply(error: error, mode: mode)
        }

        setLoadingFlags(for: mode, isLoading: false)
        isRequestInFlight = false
    }

    private func merge(page: CursorPage<OrderSummary>, mode: LoadingMode) {
        switch mode {
        case .initial, .refresh:
            allOrders = deduplicated(page.items)
        case .loadMore:
            let existingIDs = Set(allOrders.map(\.id))
            let appended = page.items.filter { !existingIDs.contains($0.id) }
            allOrders.append(contentsOf: appended)
        }

        viewState.nextCursor = normalize(cursor: page.nextCursor)
        viewState.canLoadMore = viewState.nextCursor != nil
        viewState.emptyState = nil
        viewState.requiresAuthentication = false
    }

    private func applyOrders(resetErrorMessage: Bool) {
        let filteredOrders = allOrders.filter { viewState.selectedFilter.includes(status: $0.status) }
        viewState.orders = filteredOrders.map(mapListItem)

        if resetErrorMessage {
            viewState.errorMessage = nil
        }

        if filteredOrders.isEmpty {
            viewState.emptyState = makeEmptyState()
        } else {
            viewState.emptyState = nil
        }
    }

    private func apply(error: Error, mode: LoadingMode) {
        let featureError = (error as? OrderFeatureError) ?? .unavailable(message: "주문 내역을 불러오지 못했어요.")

        if case .authenticationRequired = featureError {
            allOrders = []
            viewState.orders = []
            viewState.requiresAuthentication = true
            viewState.emptyState = OrderEmptyState(
                title: "로그인이 필요해요",
                message: featureError.userMessage,
                actionTitle: "로그인하러 가기",
                requiresAuthentication: true
            )
            viewState.errorMessage = nil
            viewState.canLoadMore = false
            viewState.nextCursor = nil
            return
        }

        if allOrders.isEmpty || mode != .loadMore {
            viewState.emptyState = OrderEmptyState(
                title: mode == .refresh ? "주문 내역을 새로고침하지 못했어요" : "주문 내역을 불러오지 못했어요",
                message: featureError.userMessage,
                actionTitle: "다시 시도",
                requiresAuthentication: false
            )
        } else {
            viewState.errorMessage = featureError.userMessage
        }
        viewState.canLoadMore = false
        viewState.nextCursor = nil
    }

    private func attemptAutoNavigationIfNeeded() async {
        guard let highlightedOrderID = viewState.highlightedOrderID,
              !hasAutoNavigatedHighlightedOrder,
              viewState.orders.contains(where: { $0.id == highlightedOrderID }) else {
            return
        }

        hasAutoNavigatedHighlightedOrder = true
        router.routeToOrderDetail(orderID: highlightedOrderID)
    }

    private func setLoadingFlags(for mode: LoadingMode, isLoading: Bool) {
        switch mode {
        case .initial:
            viewState.isInitialLoading = isLoading
        case .refresh:
            viewState.isRefreshing = isLoading
        case .loadMore:
            viewState.isLoadingMore = isLoading
        }
    }

    private func mapListItem(_ order: OrderSummary) -> OrderListItemViewState {
        let primaryMenuName = order.itemSummaries.first?.menuName ?? "메뉴 정보 준비 중"
        let additionalCount = max(order.itemSummaries.reduce(0) { $0 + $1.quantity } - 1, 0)
        let primaryItemText = additionalCount > 0 ? "\(primaryMenuName) 외 \(additionalCount)개" : primaryMenuName
        let createdAtText = dateParser.string(from: order.createdAt, format: "M월 d일 a h:mm")
        let pickupTimeText = order.pickupTime.map { "픽업 예상 \($0.formatted(date: .omitted, time: .shortened))" }

        return OrderListItemViewState(
            id: order.id,
            orderCode: order.orderCode,
            storeName: order.storeName,
            storeImagePath: order.storeImagePath,
            statusTitle: order.status.displayTitle,
            primaryItemText: primaryItemText,
            createdAtText: createdAtText,
            pickupTimeText: pickupTimeText,
            totalPriceText: currencyFormatter.string(from: order.totalAmount),
            isHighlighted: order.id == viewState.highlightedOrderID
        )
    }

    private func makeEmptyState() -> OrderEmptyState {
        switch viewState.selectedFilter {
        case .all:
            return OrderEmptyState(
                title: "아직 주문 내역이 없어요",
                message: "가까운 가게를 둘러보고 첫 픽업을 시작해보세요.",
                actionTitle: "가게 둘러보기",
                requiresAuthentication: false
            )
        default:
            return OrderEmptyState(
                title: "선택한 상태의 주문이 없어요",
                message: "다른 필터를 선택하거나 새로고침해 주세요.",
                actionTitle: "다시 시도",
                requiresAuthentication: false
            )
        }
    }

    private func deduplicated(_ orders: [OrderSummary]) -> [OrderSummary] {
        var seen = Set<String>()
        return orders.filter { order in
            seen.insert(order.id).inserted
        }
    }

    private func normalize(cursor: String?) -> String? {
        guard let cursor, !cursor.isEmpty, cursor != "0" else {
            return nil
        }
        return cursor
    }
}

private extension OrderPresenter {
    enum LoadingMode {
        case initial
        case refresh
        case loadMore
    }
}
