import Foundation

@MainActor
protocol ChatInteracting {
    func loadInitialState() async -> ChatViewState
}

@MainActor
struct ChatInteractor: ChatInteracting {
    private let storeID: String?

    init(storeID: String? = nil) {
        self.storeID = storeID
    }

    func loadInitialState() async -> ChatViewState {
        ChatViewState(storeID: storeID)
    }
}
