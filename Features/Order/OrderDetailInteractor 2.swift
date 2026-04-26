import Foundation

@MainActor
protocol OrderDetailInteracting {
    func loadInitialState() async -> OrderDetailViewState
    func fetchOrderDetail() async throws -> OrderDetail
}

@MainActor
struct OrderDetailInteractor: OrderDetailInteracting {
    private let orderID: String
    private let orderRepository: OrderRepository
    private let sessionStore: SessionStore

    init(
        orderID: String,
        orderRepository: OrderRepository,
        sessionStore: SessionStore
    ) {
        self.orderID = orderID
        self.orderRepository = orderRepository
        self.sessionStore = sessionStore
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
            return try await orderRepository.fetchOrderDetail(orderID: orderID)
        } catch {
            throw map(error: error)
        }
    }

    private func map(error: Error) -> OrderFeatureError {
        guard let networkError = error as? NetworkError else {
            return .unavailable(message: "주문 상세를 불러오지 못했어요.")
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
            return .unavailable(message: "주문 상세를 불러오지 못했어요.")
        }
    }
}
