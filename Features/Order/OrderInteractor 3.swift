import Foundation

@MainActor
protocol OrderInteracting {
    func loadInitialState() async -> OrderViewState
}

@MainActor
struct OrderInteractor: OrderInteracting {
    private let initialOrderID: String?

    init(initialOrderID: String? = nil) {
        self.initialOrderID = initialOrderID
    }

    func loadInitialState() async -> OrderViewState {
        if let initialOrderID {
            return OrderViewState(
                subtitle: "가장 최근 생성된 주문 \(initialOrderID)을 기준으로 주문 흐름을 확장할 수 있어요.",
                highlightedOrderID: initialOrderID
            )
        }

        return OrderViewState()
    }
}
