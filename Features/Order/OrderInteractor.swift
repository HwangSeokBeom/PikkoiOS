import Foundation

@MainActor
protocol OrderInteracting {
    func loadInitialState() async -> OrderViewState
    func fetchOrders(cursor: String?, filter: OrderListFilter) async throws -> CursorPage<OrderSummary>
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

    private func map(error: Error) -> OrderFeatureError {
        guard let networkError = error as? NetworkError else {
            return .unavailable(message: "주문 내역을 불러오지 못했어요.")
        }

        if networkError.isAuthenticationFailure {
            return .authenticationRequired
        }

        if networkError.isConfigurationFailure {
            return .configurationRequired
        }

        switch networkError {
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
