import Foundation

@MainActor
protocol StoreDetailInteracting {
    func loadInitialState() async -> StoreDetailViewState
}

@MainActor
struct StoreDetailInteractor: StoreDetailInteracting {
    func loadInitialState() async -> StoreDetailViewState {
        StoreDetailViewState()
    }
}
