import Foundation

@MainActor
protocol OrderInteracting {
    func loadInitialState() async -> OrderViewState
    func fetchOrders(cursor: String?, filter: OrderListFilter) async throws -> CursorPage<OrderSummary>
    func fetchPaymentReceipt(orderCode: String) async throws -> PaymentReceipt
    func makePendingPaymentSession(order: OrderSummary) async throws -> PendingPaymentSession
    func savePendingPaymentSession(_ session: PendingPaymentSession) async
    func updatePendingPaymentSession(orderCode: String, state: PaymentFlowState, impUID: String?) async
    func removePendingPaymentSession(orderCode: String) async
    func makePaymentRequest(pendingSession: PendingPaymentSession) async throws -> PaymentGatewayRequest
    func validatePayment(_ request: PaymentValidationRequest) async throws -> ValidatedPaymentReceipt
    func refreshOrdersAfterAlreadyValidatedPayment(orderCode: String) async -> Bool
    func cancelOrder(orderCode: String) async throws -> OrderDetail
    func cancelPendingOrderLocally(orderCode: String) async throws -> OrderDetail
    func hideOrderFromHistory(orderCode: String) async throws
    func unhideOrderFromHistory(orderCode: String) async
    func updateOrderStatus(orderCode: String, status: OrderStatus) async throws
}

@MainActor
struct OrderInteractor: OrderInteracting {
    private let initialOrderID: String?
    private let orderRepository: OrderRepository
    private let sessionStore: SessionStore
    private let localCancellationStore: LocalOrderCancellationStore
    private let hiddenOrderHistoryStore: HiddenOrderHistoryStore
    private let notificationService: AppNotificationService
    private let orderStatusSnapshotStore: OrderStatusSnapshotStore
    private let liveActivityManager: OrderLiveActivityManaging
    private let appConfiguration: AppConfiguration
    private let pendingPaymentSessionStore: PendingPaymentSessionStore

    init(
        initialOrderID: String? = nil,
        orderRepository: OrderRepository,
        sessionStore: SessionStore,
        notificationService: AppNotificationService = NoopAppNotificationService(),
        orderStatusSnapshotStore: OrderStatusSnapshotStore = InMemoryOrderStatusSnapshotStore(),
        liveActivityManager: OrderLiveActivityManaging = NoopOrderLiveActivityManager.shared,
        appConfiguration: AppConfiguration = AppConfiguration(),
        pendingPaymentSessionStore: PendingPaymentSessionStore = .shared,
        localCancellationStore: LocalOrderCancellationStore = .shared,
        hiddenOrderHistoryStore: HiddenOrderHistoryStore = .shared
    ) {
        self.initialOrderID = initialOrderID
        self.orderRepository = orderRepository
        self.sessionStore = sessionStore
        self.notificationService = notificationService
        self.orderStatusSnapshotStore = orderStatusSnapshotStore
        self.liveActivityManager = liveActivityManager
        self.appConfiguration = appConfiguration
        self.pendingPaymentSessionStore = pendingPaymentSessionStore
        self.localCancellationStore = localCancellationStore
        self.hiddenOrderHistoryStore = hiddenOrderHistoryStore
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
            let mergedPage = await applyLocalStores(to: page)
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

    func makePendingPaymentSession(order: OrderSummary) async throws -> PendingPaymentSession {
        guard let userID = sessionStore.currentUserID?.trimmingCharacters(in: .whitespacesAndNewlines),
              !userID.isEmpty else {
            throw OrderFeatureError.authenticationRequired
        }
        return PendingPaymentSession(
            userID: userID,
            orderCode: order.orderCode,
            orderID: order.id,
            storeID: order.storeID,
            storeName: order.storeName,
            menuSummary: order.paymentRecoveryDisplayName,
            totalPriceAmount: order.totalAmount,
            createdAt: order.createdAt,
            state: .recoverablePending,
            impUID: nil,
            lastUpdatedAt: Date()
        )
    }

    func savePendingPaymentSession(_ session: PendingPaymentSession) async {
        await pendingPaymentSessionStore.upsert(session)
    }

    func updatePendingPaymentSession(orderCode: String, state: PaymentFlowState, impUID: String?) async {
        guard let userID = sessionStore.currentUserID?.trimmingCharacters(in: .whitespacesAndNewlines),
              !userID.isEmpty else { return }
        await pendingPaymentSessionStore.update(orderCode: orderCode, userID: userID, state: state, impUID: impUID)
    }

    func removePendingPaymentSession(orderCode: String) async {
        guard let userID = sessionStore.currentUserID?.trimmingCharacters(in: .whitespacesAndNewlines),
              !userID.isEmpty else { return }
        await pendingPaymentSessionStore.remove(orderCode: orderCode, userID: userID)
    }

    func makePaymentRequest(pendingSession: PendingPaymentSession) async throws -> PaymentGatewayRequest {
        try makePaymentRequest(
            orderID: pendingSession.orderID ?? pendingSession.orderCode,
            orderCode: pendingSession.orderCode,
            amount: pendingSession.totalPriceAmount,
            displayName: pendingSession.menuSummary
        )
    }

    func validatePayment(_ request: PaymentValidationRequest) async throws -> ValidatedPaymentReceipt {
        do {
            return try await orderRepository.validatePayment(request)
        } catch let error as NetworkError {
            if case .conflict = error {
                throw OrderFeatureError.alreadyValidated
            }
            throw map(error: error, fallbackMessage: "결제 확인에 실패했어요.")
        } catch {
            throw map(error: error, fallbackMessage: "결제 확인에 실패했어요.")
        }
    }

    func refreshOrdersAfterAlreadyValidatedPayment(orderCode: String) async -> Bool {
        do {
            let page = try await orderRepository.fetchOrders(cursor: nil, filter: nil, forceRefresh: true)
            return page.items.contains { $0.orderCode == orderCode && $0.isPaymentCompleted }
        } catch {
            Logger.shared.warning("[PaymentRecovery] alreadyValidated orderRefreshFailed orderCode=\(orderCode) message=\(error.localizedDescription)")
            return false
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

    private func applyLocalStores(to page: CursorPage<OrderSummary>) async -> CursorPage<OrderSummary> {
        guard let userID = sessionStore.currentUserID else {
            return page
        }
        let cancellationApplied = await localCancellationStore.apply(to: page.items, userID: userID)
        return CursorPage(
            items: await hiddenOrderHistoryStore.apply(to: cancellationApplied, userID: userID),
            nextCursor: page.nextCursor
        )
    }

    func hideOrderFromHistory(orderCode: String) async throws {
        guard let userID = sessionStore.currentUserID else {
            throw OrderFeatureError.authenticationRequired
        }
        let page = try await orderRepository.fetchOrders(cursor: nil, filter: nil)
        guard let order = page.items.first(where: { $0.orderCode == orderCode || $0.id == orderCode }) else {
            throw OrderFeatureError.notFound
        }
        guard order.status.isTerminal else {
            throw OrderFeatureError.unavailable(message: "진행 중인 주문은 숨길 수 없어요.")
        }
        await hiddenOrderHistoryStore.hide(order: order, userID: userID)
    }

    func unhideOrderFromHistory(orderCode: String) async {
        guard let userID = sessionStore.currentUserID else { return }
        await hiddenOrderHistoryStore.unhide(orderCode: orderCode, userID: userID)
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

    private func makePaymentRequest(
        orderID: String,
        orderCode: String,
        amount: Decimal,
        displayName: String
    ) throws -> PaymentGatewayRequest {
        let merchantUID = orderCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !merchantUID.isEmpty, amount > 0 else {
            throw OrderFeatureError.unavailable(message: "주문 결제 정보를 확인하지 못했어요.")
        }
        guard let userCode = appConfiguration.portOneUserCode?.trimmingCharacters(in: .whitespacesAndNewlines),
              !userCode.isEmpty else {
            throw OrderFeatureError.configurationRequired
        }
        let buyerName = sessionStore.nick?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "Pikko 고객"
        return PaymentGatewayRequest(
            orderID: orderID,
            merchantUID: merchantUID,
            amount: amount,
            orderName: displayName.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "Pikko 주문",
            buyerName: buyerName,
            pg: appConfiguration.portOnePg,
            pgID: appConfiguration.portOnePgID,
            payMethod: appConfiguration.portOnePayMethod,
            appScheme: appConfiguration.portOneAppScheme,
            userCode: userCode,
            isTestMode: appConfiguration.isPaymentTestMode
        )
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

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
