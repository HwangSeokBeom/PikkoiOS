import Foundation

@MainActor
protocol AuthInteracting {
    func loadInitialState() async -> AuthViewState
    func signInStub() async throws -> UserSession
}

@MainActor
struct AuthInteractor: AuthInteracting {
    private let authRepository: AuthRepository

    init(authRepository: AuthRepository) {
        self.authRepository = authRepository
    }

    func loadInitialState() async -> AuthViewState {
        AuthViewState()
    }

    func signInStub() async throws -> UserSession {
        try await authRepository.signInStub()
    }
}
