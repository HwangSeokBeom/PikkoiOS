import Foundation

@MainActor
protocol CommunityInteracting {
    func loadInitialState() async -> CommunityViewState
}

@MainActor
struct CommunityInteractor: CommunityInteracting {
    func loadInitialState() async -> CommunityViewState {
        CommunityViewState()
    }
}
