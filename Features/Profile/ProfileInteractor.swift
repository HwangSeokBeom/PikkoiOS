import Foundation

@MainActor
protocol ProfileInteracting {
    func loadInitialState() async -> ProfileViewState
}

@MainActor
struct ProfileInteractor: ProfileInteracting {
    private let sessionStore: SessionStore

    init(sessionStore: SessionStore) {
        self.sessionStore = sessionStore
    }

    func loadInitialState() async -> ProfileViewState {
        let displayName = sessionStore.currentSession?.displayName ?? "Guest"
        return ProfileViewState(
            subtitle: "Signed in as \(displayName). Account-facing feature modules can branch from this root."
        )
    }
}
