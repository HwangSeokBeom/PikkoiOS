import Foundation

@MainActor
protocol CheckoutInteracting {
    func loadInitialState() async -> CheckoutViewState
}

@MainActor
struct CheckoutInteractor: CheckoutInteracting {
    func loadInitialState() async -> CheckoutViewState {
        CheckoutViewState()
    }
}
