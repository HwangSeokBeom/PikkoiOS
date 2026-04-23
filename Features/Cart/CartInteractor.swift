import Foundation

@MainActor
protocol CartInteracting {
    func loadInitialState() async -> CartViewState
}

@MainActor
struct CartInteractor: CartInteracting {
    private let cartStore: CartStore

    init(cartStore: CartStore) {
        self.cartStore = cartStore
    }

    func loadInitialState() async -> CartViewState {
        CartViewState(
            subtitle: "Current stub cart count: \(cartStore.summary.itemCount) items. Replace this with server-backed line items later."
        )
    }
}
