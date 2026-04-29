import Foundation

@MainActor
protocol OrderInteracting {
    func loadInitialState() async -> OrderViewState
    func fetchOrders(cursor: String?, filter: OrderListFilter) async throws -> CursorPage<OrderSummary>
    func fetchPaymentReceipt(orderCode: String) async throws -> PaymentReceipt
    func cancelOrder(orderCode: String) async throws -> OrderDetail
    func updateOrderStatus(orderCode: String, status: OrderStatus) async throws
}

@MainActor
struct OrderInteractor: OrderInteracting {
    private let initialOrderID: String?
    private let orderRepository: OrderRepository
    private let sessionStore: SessionStore

    init(
        initialOrderID: String? = nil,
        orderRepository: OrderRepository,
        sessionStore: SessionStore
    ) {
        self.initialOrderID = initialOrderID
        self.orderRepository = orderRepository
        self.sessionStore = sessionStore
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
            return try await orderRepository.fetchOrders(cursor: cursor, filter: filter == .all ? nil : filter.rawValue)
        } catch {
            throw map(error: error)
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

    func updateOrderStatus(orderCode: String, status: OrderStatus) async throws {
        do {
            try await orderRepository.updateOrderStatus(orderCode: orderCode, status: status)
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
