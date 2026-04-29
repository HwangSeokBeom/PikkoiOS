import Combine
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
    private var cancellables = Set<AnyCancellable>()

    init(interactor: OrderInteracting, router: OrderRouting) {
        self.interactor = interactor
        self.router = router
        bindOrderStatusChanges()
        bindOrderRefreshRequests()
    }

    func send(_ action: OrderAction) async {
        switch action {
        case .onAppear:
            guard !hasLoaded else { return }
            hasLoaded = true
            viewState = await interactor.loadInitialState()
            guard viewState.isInitialLoading else { return }
            _ = await loadOrders(mode: .initial)

        case .refreshRequested:
            _ = await loadOrders(mode: .refresh)

        case .retryTapped:
            _ = await loadOrders(mode: viewState.orders.isEmpty ? .initial : .refresh)

        case .filterTapped(let filter):
            guard viewState.selectedFilter != filter else { return }
            viewState.selectedFilter = filter
            applyOrders(resetErrorMessage: false)
            await attemptAutoNavigationIfNeeded()

        case .orderTapped(let orderID):
            router.routeToOrderDetail(orderID: orderID)

        case .cancelConfirmed(let orderID):
            await cancelOrder(orderID: orderID)

        case .statusSelected(let orderCode, let currentStatus, let nextStatus):
            Logger.shared.debug(
                "[OrderStatus] select orderCode=\(orderCode) current=\(currentStatus.displayTitle) next=\(nextStatus.displayTitle)"
            )

        case .statusChangeConfirmed(let orderCode, let nextStatus):
            await updateOrderStatus(orderCode: orderCode, nextStatus: nextStatus)

        case .orderAppeared(let orderID):
            guard orderID == viewState.orders.last?.id,
                  viewState.canLoadMore,
                  !viewState.isLoadingMore,
                  !isRequestInFlight else { return }
            _ = await loadOrders(mode: .loadMore)

        case .loginRequiredTapped:
            router.routeToAuth()

        case .exploreStoresTapped:
            router.routeToExploreHome()
        }
    }

    @discardableResult
    private func loadOrders(mode: LoadingMode) async -> Bool {
        guard !isRequestInFlight else { return false }
        isRequestInFlight = true
        setLoadingFlags(for: mode, isLoading: true)
        if mode != .loadMore {
            viewState.errorMessage = nil
            viewState.successMessage = nil
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
            setLoadingFlags(for: mode, isLoading: false)
            isRequestInFlight = false
            return false
        }

        setLoadingFlags(for: mode, isLoading: false)
        isRequestInFlight = false
        return true
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
        let totalItemCount = order.itemSummaries.reduce(0) { $0 + $1.quantity }
        let additionalCount = max(totalItemCount - 1, 0)
        let primaryItemText = additionalCount > 0 ? "\(primaryMenuName) 외 \(additionalCount)개" : primaryMenuName
        let createdAtText = dateParser.string(from: order.createdAt, format: "M월 d일 a h:mm")
        let pickupTimeText = order.pickupTime.map { "픽업 예상 \($0.formatted(date: .omitted, time: .shortened))" }
        let allowedNextStatus = order.isPaymentCompleted ? order.status.allowedNextStatus : nil

        return OrderListItemViewState(
            id: order.id,
            orderCode: order.orderCode,
            storeName: order.storeName,
            storeImagePath: order.storeImagePath,
            status: order.status,
            statusTitle: order.status.displayTitle,
            statusSteps: makeProgressSteps(for: order.status),
            primaryItemText: primaryItemText,
            itemRows: order.itemSummaries.map(makeMenuItemRow),
            itemCountText: "\(totalItemCount)EA",
            createdAtText: createdAtText,
            pickupTimeText: pickupTimeText,
            totalPriceText: currencyFormatter.string(from: order.totalAmount),
            reviewRatingText: order.reviewRating.map { rating in
                let value = NSDecimalNumber(decimal: rating).doubleValue
                return String(format: "%.1f", value)
            },
            isHighlighted: order.id == viewState.highlightedOrderID,
            canCancel: order.canCancel,
            isCancelling: viewState.cancellingOrderIDs.contains(order.id),
            isStatusUpdating: viewState.statusUpdatingOrderCodes.contains(order.orderCode),
            isPaymentCompleted: order.isPaymentCompleted,
            allowedNextStatus: allowedNextStatus,
            statusChangeMessage: order.isPaymentCompleted ? nil : "결제 검증 완료 후 상태 변경이 가능합니다.",
            isPastOrder: order.status.isTerminal,
            canWriteReview: order.status == .completed && order.reviewID == nil
        )
    }

    private func makeMenuItemRow(_ item: OrderItemSummary) -> OrderMenuItemViewState {
        OrderMenuItemViewState(
            id: item.id,
            name: item.menuName,
            quantityText: "\(item.quantity)EA",
            priceText: item.unitPriceAmount.map { currencyFormatter.string(from: $0) } ?? "-",
            imagePath: item.imagePath
        )
    }

    private func makeProgressSteps(for status: OrderStatus) -> [OrderProgressStepViewState] {
        let orderedStatuses: [OrderStatus] = [.pending, .accepted, .preparing, .ready, .completed]

        if status.isExceptionTerminal || status.progressStepIndex == nil {
            return [
                OrderProgressStepViewState(
                    id: status.displayTitle,
                    title: status.displayTitle,
                    timeText: status.isExceptionTerminal ? "주문이 종료되었어요" : nil,
                    state: status.isExceptionTerminal ? .exception : .current
                )
            ]
        }

        let currentIndex = status.progressStepIndex ?? 0
        return orderedStatuses.enumerated().map { index, stepStatus in
            let state: OrderProgressStepViewState.State
            if index < currentIndex {
                state = .completed
            } else if index == currentIndex {
                state = .current
            } else {
                state = .pending
            }

            return OrderProgressStepViewState(
                id: stepStatus.displayTitle,
                title: stepStatus.displayTitle,
                timeText: nil,
                state: state
            )
        }
    }

    private func cancelOrder(orderID: String) async {
        guard let order = allOrders.first(where: { $0.id == orderID }),
              order.canCancel,
              !viewState.cancellingOrderIDs.contains(orderID) else { return }

        viewState.cancellingOrderIDs.insert(orderID)
        viewState.errorMessage = nil
        viewState.successMessage = nil
        applyOrders(resetErrorMessage: false)

        do {
            let detail = try await interactor.cancelOrder(orderCode: order.orderCode)
            upsert(detail: detail)
            viewState.successMessage = "주문이 취소되었어요."
        } catch {
            let featureError = (error as? OrderFeatureError)
                ?? .unavailable(message: "주문을 취소하지 못했어요. 잠시 후 다시 시도해주세요.")
            viewState.errorMessage = featureError.userMessage
        }

        viewState.cancellingOrderIDs.remove(orderID)
        applyOrders(resetErrorMessage: false)
    }

    private func updateOrderStatus(orderCode: String, nextStatus: OrderStatus) async {
        guard let order = allOrders.first(where: { $0.orderCode == orderCode }),
              order.status != nextStatus,
              !viewState.statusUpdatingOrderCodes.contains(orderCode) else { return }

        let allowedNextStatus = order.status.allowedNextStatus
        Logger.shared.debug(
            "[OrderStatus] eligibility orderCode=\(orderCode) isPaymentCompleted=\(order.isPaymentCompleted) currentStatus=\(order.status.apiValue) allowedNextStatus=\(allowedNextStatus?.apiValue ?? "nil")"
        )
        guard order.isPaymentCompleted else {
            viewState.errorMessage = "결제 검증 완료 후 상태 변경이 가능합니다."
            return
        }
        guard order.status.canTransition(to: nextStatus) else {
            viewState.errorMessage = "현재 주문 상태에서 다음 단계만 변경할 수 있어요."
            return
        }

        Logger.shared.debug(
            "[OrderStatus] confirm orderCode=\(orderCode) next=\(nextStatus.displayTitle)"
        )
        viewState.statusUpdatingOrderCodes.insert(orderCode)
        viewState.errorMessage = nil
        viewState.successMessage = nil
        applyOrders(resetErrorMessage: false)

        do {
            let receipt = try await interactor.fetchPaymentReceipt(orderCode: orderCode)
            Logger.shared.debug(
                "[OrderStatus] eligibility orderCode=\(orderCode) isPaymentCompleted=\(receipt.isPaymentCompleted) currentStatus=\(order.status.apiValue) allowedNextStatus=\(allowedNextStatus?.apiValue ?? "nil")"
            )
            guard receipt.isPaymentCompleted else {
                throw OrderFeatureError.unavailable(message: "결제 검증 완료 후 상태 변경이 가능합니다.")
            }
            try await interactor.updateOrderStatus(orderCode: orderCode, status: nextStatus)
            _ = await loadOrders(mode: .refresh)
            viewState.successMessage = "주문 상태가 변경되었습니다."
            Logger.shared.debug(
                "[OrderStatus] success orderCode=\(orderCode) next=\(nextStatus.displayTitle)"
            )
        } catch {
            let featureError = (error as? OrderFeatureError)
                ?? .unavailable(message: "주문 상태 변경에 실패했어요. 다시 시도해 주세요.")
            viewState.errorMessage = featureError.userMessage
            Logger.shared.error(
                "[OrderStatus] failed orderCode=\(orderCode) next=\(nextStatus.displayTitle) error=\(error.localizedDescription)"
            )
        }

        viewState.statusUpdatingOrderCodes.remove(orderCode)
        applyOrders(resetErrorMessage: false)
    }

    private func upsert(detail: OrderDetail) {
        let summary = makeSummary(from: detail)
        if let index = allOrders.firstIndex(where: { $0.id == detail.orderID || $0.orderCode == detail.orderCode }) {
            allOrders[index] = summary
        } else {
            allOrders.insert(summary, at: 0)
        }
    }

    private func makeSummary(from detail: OrderDetail) -> OrderSummary {
        OrderSummary(
            id: detail.orderID,
            orderCode: detail.orderCode,
            storeID: detail.storeID,
            storeName: detail.storeName,
            storeImagePath: detail.storeImagePath,
            status: detail.status,
            createdAt: detail.createdAt,
            paidAt: detail.paidAt,
            totalAmount: detail.totalAmount,
            itemSummaries: detail.items,
            pickupTime: detail.pickupTime,
            reviewID: detail.reviewID,
            reviewRating: detail.reviewRating
        )
    }

    private func bindOrderStatusChanges() {
        NotificationCenter.default.publisher(for: .pikkoOrderStatusDidChange)
            .receive(on: RunLoop.main)
            .sink { [weak self] notification in
                guard let event = notification.userInfo?[OrderStatusChangeNotificationUserInfoKey.event] as? OrderStatusChangeNotification else {
                    return
                }

                Task { @MainActor [weak self] in
                    self?.apply(statusChange: event)
                }
            }
            .store(in: &cancellables)
    }

    private func bindOrderRefreshRequests() {
        NotificationCenter.default.publisher(for: .pikkoOrdersShouldRefresh)
            .receive(on: RunLoop.main)
            .sink { [weak self] notification in
                guard let event = notification.userInfo?[OrderRefreshNotificationUserInfoKey.event] as? OrderRefreshNotification else {
                    return
                }

                Task { @MainActor [weak self] in
                    await self?.handle(refreshRequest: event)
                }
            }
            .store(in: &cancellables)
    }

    private func handle(refreshRequest event: OrderRefreshNotification) async {
        if let orderID = event.orderID {
            viewState.highlightedOrderID = orderID
            hasAutoNavigatedHighlightedOrder = false
        }

        guard hasLoaded else { return }

        let refreshed = await loadOrders(mode: .refresh)
        guard refreshed else { return }

        let matchedOrder = allOrders.first { order in
            event.orderID.map { $0 == order.id } == true
                || event.orderCode.map { $0 == order.orderCode } == true
        }
        if matchedOrder == nil {
            viewState.successMessage = event.message ?? "주문이 접수되었습니다. 목록 반영까지 잠시 걸릴 수 있습니다."
        } else {
            viewState.successMessage = "주문 내역을 최신 상태로 새로고침했어요."
        }
    }

    private func apply(statusChange event: OrderStatusChangeNotification) {
        guard let index = allOrders.firstIndex(where: { order in
            order.orderCode == event.orderCode || event.orderID == order.id
        }) else {
            return
        }

        let existing = allOrders[index]
        allOrders[index] = OrderSummary(
            id: existing.id,
            orderCode: existing.orderCode,
            storeID: existing.storeID,
            storeName: existing.storeName,
            storeImagePath: existing.storeImagePath,
            status: event.status,
            createdAt: existing.createdAt,
            paidAt: existing.paidAt,
            totalAmount: existing.totalAmount,
            itemSummaries: existing.itemSummaries,
            pickupTime: existing.pickupTime,
            reviewID: existing.reviewID,
            reviewRating: existing.reviewRating
        )
        viewState.cancellingOrderIDs.remove(existing.id)
        applyOrders(resetErrorMessage: false)
    }

    private func applyStatus(orderCode: String, status: OrderStatus) {
        guard let index = allOrders.firstIndex(where: { $0.orderCode == orderCode }) else {
            return
        }

        let existing = allOrders[index]
        allOrders[index] = OrderSummary(
            id: existing.id,
            orderCode: existing.orderCode,
            storeID: existing.storeID,
            storeName: existing.storeName,
            storeImagePath: existing.storeImagePath,
            status: status,
            createdAt: existing.createdAt,
            paidAt: existing.paidAt,
            totalAmount: existing.totalAmount,
            itemSummaries: existing.itemSummaries,
            pickupTime: existing.pickupTime,
            reviewID: existing.reviewID,
            reviewRating: existing.reviewRating
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
