import Foundation

@MainActor
protocol OrderInteracting {
    func loadInitialState() async -> OrderViewState
    func fetchOrders(cursor: String?, filter: OrderListFilter) async throws -> CursorPage<OrderSummary>
    func fetchPaymentReceipt(orderCode: String) async throws -> PaymentReceipt
    func cancelOrder(orderCode: String) async throws -> OrderDetail
    func cancelPendingOrderLocally(orderCode: String) async throws -> OrderDetail
    func updateOrderStatus(orderCode: String, status: OrderStatus) async throws
}

@MainActor
struct OrderInteractor: OrderInteracting {
    private let initialOrderID: String?
    private let orderRepository: OrderRepository
    private let sessionStore: SessionStore
    private let localCancellationStore: LocalOrderCancellationStore
    private let notificationService: AppNotificationService
    private let orderStatusSnapshotStore: OrderStatusSnapshotStore
    private let liveActivityManager: OrderLiveActivityManaging

    init(
        initialOrderID: String? = nil,
        orderRepository: OrderRepository,
        sessionStore: SessionStore,
        notificationService: AppNotificationService = NoopAppNotificationService(),
        orderStatusSnapshotStore: OrderStatusSnapshotStore = InMemoryOrderStatusSnapshotStore(),
        liveActivityManager: OrderLiveActivityManaging = NoopOrderLiveActivityManager.shared,
        localCancellationStore: LocalOrderCancellationStore = .shared
    ) {
        self.initialOrderID = initialOrderID
        self.orderRepository = orderRepository
        self.sessionStore = sessionStore
        self.notificationService = notificationService
        self.orderStatusSnapshotStore = orderStatusSnapshotStore
        self.liveActivityManager = liveActivityManager
        self.localCancellationStore = localCancellationStore
    }

    func loadInitialState() async -> OrderViewState {
        var state = OrderViewState()
        state.highlightedOrderID = initialOrderID
        if sessionStore.isAuthenticated {
            state.isInitialLoading = true
        } else {
            state.emptyState = OrderEmptyState(
                title: "로그인이 필요해요",
                message: "주문 내역과 픽업 진행 상황은 로그인 후 확인할 수 있어요.",
                actionTitle: "로그인하기",
                requiresAuthentication: true
            )
            state.requiresAuthentication = true
        }
        return state
    }

    func fetchOrders(cursor: String?, filter: OrderListFilter) async throws -> CursorPage<OrderSummary> {
        do {
            let page = try await orderRepository.fetchOrders(cursor: cursor, filter: filter == .all ? nil : filter.rawValue)
            let mergedPage = await applyLocalCancellations(to: page)
            if cursor == nil {
                detectOrderStatusChanges(in: mergedPage.items)
                liveActivityManager.sync(orders: mergedPage.items, source: "orderList")
            }
            return mergedPage
        } catch {
            throw map(error: error)
        }
    }

    private func detectOrderStatusChanges(in orders: [OrderSummary]) {
        for order in orders {
            let currentStatus = order.status.apiValue
            guard !order.orderCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }

            if let previousStatus = orderStatusSnapshotStore.status(for: order.orderCode) {
                if previousStatus != currentStatus {
                    notificationService.handleOrderStatusChanged(
                        orderCode: order.orderCode,
                        previousStatus: previousStatus,
                        currentStatus: currentStatus,
                        storeName: order.storeName
                    )
                }
            }

            orderStatusSnapshotStore.saveStatus(currentStatus, for: order.orderCode)
        }
    }

    func fetchPaymentReceipt(orderCode: String) async throws -> PaymentReceipt {
        do {
            return try await orderRepository.fetchPaymentReceipt(orderCode: orderCode)
        } catch {
            throw map(error: error, fallbackMessage: "결제 영수증을 확인하지 못했어요.")
        }
    }

    func cancelOrder(orderCode: String) async throws -> OrderDetail {
        do {
            return try await orderRepository.cancelOrder(orderCode: orderCode)
        } catch {
            throw map(error: error, fallbackMessage: "주문을 취소하지 못했어요. 잠시 후 다시 시도해주세요.")
        }
    }

    func cancelPendingOrderLocally(orderCode: String) async throws -> OrderDetail {
        guard let userID = sessionStore.currentUserID else {
            throw OrderFeatureError.authenticationRequired
        }

        let page = try await orderRepository.fetchOrders(cursor: nil, filter: nil)
        guard let order = page.items.first(where: { $0.orderCode == orderCode || $0.id == orderCode }) else {
            throw OrderFeatureError.notFound
        }
        guard order.status == .pending else {
            throw OrderFeatureError.unavailable(message: "매장 승인 후에는 앱에서 취소할 수 없어요.")
        }
        guard !hasPaymentIdentifier(order), !order.isPaymentCompleted else {
            throw OrderFeatureError.unavailable(message: "결제 취소 API가 필요해요. 매장에 문의해 주세요.")
        }

        await localCancellationStore.save(order: order, userID: userID)
        let detail = try await orderRepository.fetchOrderDetail(orderID: order.id)
        return await localCancellationStore.apply(to: detail, userID: userID)
    }

    private func applyLocalCancellations(to page: CursorPage<OrderSummary>) async -> CursorPage<OrderSummary> {
        guard let userID = sessionStore.currentUserID else {
            return page
        }

        return CursorPage(
            items: await localCancellationStore.apply(to: page.items, userID: userID),
            nextCursor: page.nextCursor
        )
    }

    private func hasPaymentIdentifier(_ order: OrderSummary) -> Bool {
        [
            order.paymentLookupKey,
            order.paymentID,
            order.merchantUID,
            order.impUID
        ].contains { value in
            value?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        }
    }

    func updateOrderStatus(orderCode: String, status: OrderStatus) async throws {
        do {
            try await orderRepository.updateOrderStatus(orderCode: orderCode, status: status)
            let page = try? await orderRepository.fetchOrders(cursor: nil, filter: nil, forceRefresh: true)
            if let order = page?.items.first(where: { $0.orderCode == orderCode || $0.id == orderCode }) {
                if status == .completed {
                    liveActivityManager.end(order: order, reason: .pickedUp)
                } else {
                    liveActivityManager.update(order: order)
                }
            }
        } catch {
            throw map(error: error, fallbackMessage: "주문 상태 변경에 실패했어요. 다시 시도해 주세요.")
        }
    }

    private func map(
        error: Error,
        fallbackMessage: String = "주문 내역을 불러오지 못했어요."
    ) -> OrderFeatureError {
        guard let networkError = error as? NetworkError else {
            return .unavailable(message: fallbackMessage)
        }

        if networkError.isAuthenticationFailure {
            return .authenticationRequired
        }

        if networkError.isConfigurationFailure {
            return .configurationRequired
        }

        switch networkError {
        case .abnormalRequest(let message):
            return .unavailable(message: message)
        case .notFound:
            return .notFound
        case .businessAuthorization(let message),
             .conflict(let message),
             .server(let message):
            return .unavailable(message: message)
        case .transport:
            return .unavailable(message: "네트워크 상태를 확인한 뒤 다시 시도해 주세요.")
        default:
            return .unavailable(message: "주문 내역을 불러오지 못했어요.")
        }
    }
}
