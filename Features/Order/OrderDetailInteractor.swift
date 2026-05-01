import Foundation

@MainActor
protocol OrderDetailInteracting {
    func loadInitialState() async -> OrderDetailViewState
    func fetchOrderDetail() async throws -> OrderDetail
    func cancelOrder(orderCode: String) async throws -> OrderDetail
    func cancelPendingOrderLocally(orderCode: String) async throws -> OrderDetail
}

@MainActor
struct OrderDetailInteractor: OrderDetailInteracting {
    private let orderID: String
    private let orderRepository: OrderRepository
    private let sessionStore: SessionStore
    private let localCancellationStore: LocalOrderCancellationStore

    init(
        orderID: String,
        orderRepository: OrderRepository,
        sessionStore: SessionStore,
        localCancellationStore: LocalOrderCancellationStore = .shared
    ) {
        self.orderID = orderID
        self.orderRepository = orderRepository
        self.sessionStore = sessionStore
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
