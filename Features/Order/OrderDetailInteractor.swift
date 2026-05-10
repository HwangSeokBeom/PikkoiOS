import Foundation

@MainActor
protocol OrderDetailInteracting {
    func loadInitialState() async -> OrderDetailViewState
    func fetchOrderDetail() async throws -> OrderDetail
    func makePendingPaymentSession(detail: OrderDetail) async throws -> PendingPaymentSession
    func savePendingPaymentSession(_ session: PendingPaymentSession) async
    func updatePendingPaymentSession(orderCode: String, state: PaymentFlowState, impUID: String?) async
    func removePendingPaymentSession(orderCode: String) async
    func makePaymentRequest(pendingSession: PendingPaymentSession) async throws -> PaymentGatewayRequest
    func validatePayment(_ request: PaymentValidationRequest) async throws -> ValidatedPaymentReceipt
    func fetchPaymentReceipt(orderCode: String) async throws -> PaymentReceipt
    func refreshOrdersAfterAlreadyValidatedPayment(orderCode: String) async -> Bool
    func cancelOrder(orderCode: String) async throws -> OrderDetail
    func cancelPendingOrderLocally(orderCode: String) async throws -> OrderDetail
}

@MainActor
struct OrderDetailInteractor: OrderDetailInteracting {
    private let orderID: String
    private let orderRepository: OrderRepository
    private let sessionStore: SessionStore
    private let localCancellationStore: LocalOrderCancellationStore
    private let appConfiguration: AppConfiguration
    private let pendingPaymentSessionStore: PendingPaymentSessionStore

    init(
        orderID: String,
        orderRepository: OrderRepository,
        sessionStore: SessionStore,
        appConfiguration: AppConfiguration = AppConfiguration(),
        pendingPaymentSessionStore: PendingPaymentSessionStore = .shared,
        localCancellationStore: LocalOrderCancellationStore = .shared
    ) {
        self.orderID = orderID
        self.orderRepository = orderRepository
        self.sessionStore = sessionStore
        self.appConfiguration = appConfiguration
        self.pendingPaymentSessionStore = pendingPaymentSessionStore
        self.localCancellationStore = localCancellationStore
    }

    func loadInitialState() async -> OrderDetailViewState {
        var state = OrderDetailViewState(orderID: orderID)
        if sessionStore.isAuthenticated {
            state.isLoading = true
        } else {
            state.emptyState = OrderEmptyState(
                title: "로그인이 필요해요",
                message: "사용자별 주문 상세는 로그인 후 확인할 수 있어요.",
                actionTitle: "로그인하러 가기",
                requiresAuthentication: true
            )
        }
        return state
    }

    func fetchOrderDetail() async throws -> OrderDetail {
        do {
            let detail = try await orderRepository.fetchOrderDetail(orderID: orderID)
            guard let userID = sessionStore.currentUserID else {
                return detail
            }
            return await localCancellationStore.apply(to: detail, userID: userID)
        } catch {
            throw map(error: error)
        }
    }

    func makePendingPaymentSession(detail: OrderDetail) async throws -> PendingPaymentSession {
        guard let userID = sessionStore.currentUserID?.trimmingCharacters(in: .whitespacesAndNewlines),
              !userID.isEmpty else {
            throw OrderFeatureError.authenticationRequired
        }
        return PendingPaymentSession(
            userID: userID,
            orderCode: detail.orderCode,
            orderID: detail.orderID,
            storeID: detail.storeID,
            storeName: detail.storeName,
            menuSummary: detail.paymentRecoveryDisplayName,
            totalPriceAmount: detail.totalAmount,
            createdAt: detail.createdAt,
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
        let merchantUID = pendingSession.orderCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !merchantUID.isEmpty, pendingSession.totalPriceAmount > 0 else {
            throw OrderFeatureError.unavailable(message: "주문 결제 정보를 확인하지 못했어요.")
        }
        guard let userCode = appConfiguration.portOneUserCode?.trimmingCharacters(in: .whitespacesAndNewlines),
              !userCode.isEmpty else {
            throw OrderFeatureError.configurationRequired
        }
        let buyerName = sessionStore.nick?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "Pikko 고객"
        return PaymentGatewayRequest(
            orderID: pendingSession.orderID ?? pendingSession.orderCode,
            merchantUID: merchantUID,
            amount: pendingSession.totalPriceAmount,
            orderName: pendingSession.menuSummary.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "Pikko 주문",
            buyerName: buyerName,
            pg: appConfiguration.portOnePg,
            pgID: appConfiguration.portOnePgID,
            payMethod: appConfiguration.portOnePayMethod,
            appScheme: appConfiguration.portOneAppScheme,
            userCode: userCode,
            isTestMode: appConfiguration.isPaymentTestMode
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

    func fetchPaymentReceipt(orderCode: String) async throws -> PaymentReceipt {
        do {
            return try await orderRepository.fetchPaymentReceipt(orderCode: orderCode)
        } catch {
            throw map(error: error, fallbackMessage: "결제 영수증을 확인하지 못했어요.")
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
        if let order = page.items.first(where: { $0.orderCode == orderCode || $0.id == orderID }) {
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

        let detail = try await orderRepository.fetchOrderDetail(orderID: orderID)
        guard detail.status == .pending else {
            throw OrderFeatureError.unavailable(message: "매장 승인 후에는 앱에서 취소할 수 없어요.")
        }
        guard detail.paidAt == nil,
              detail.paymentSummary?.paidAt == nil,
              detail.paymentSummary?.receiptURL == nil,
              detail.paymentSummary?.statusText?.lowercased() != "paid" else {
            throw OrderFeatureError.unavailable(message: "결제 취소 API가 필요해요. 매장에 문의해 주세요.")
        }

        await localCancellationStore.save(detail: detail, userID: userID)
        return await localCancellationStore.apply(to: detail, userID: userID)
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

    private func map(
        error: Error,
        fallbackMessage: String = "주문 상세를 불러오지 못했어요."
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
            return .unavailable(message: fallbackMessage)
        }
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
