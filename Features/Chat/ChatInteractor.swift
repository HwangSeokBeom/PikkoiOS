import Foundation

@MainActor
protocol ChatInteracting {
    func loadInitialState() async -> ChatViewState
}

@MainActor
struct ChatInteractor: ChatInteracting {
    func loadInitialState() async -> ChatViewState {
        ChatViewState()
    }
}
