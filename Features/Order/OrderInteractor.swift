import Foundation

@MainActor
protocol OrderInteracting {
    func loadInitialState() async -> OrderViewState
}

@MainActor
struct OrderInteractor: OrderInteracting {
    func loadInitialState() async -> OrderViewState {
        OrderViewState()
    }
}
