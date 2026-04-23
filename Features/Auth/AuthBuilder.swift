import Foundation

@MainActor
struct AuthBuilder {
    private let authRepository: AuthRepository
    private let sessionStore: SessionStore

    init(authRepository: AuthRepository, sessionStore: SessionStore) {
        self.authRepository = authRepository
        self.sessionStore = sessionStore
    }

    func build() -> AuthRootView {
        let router = AuthRouter()
        let interactor = AuthInteractor(authRepository: authRepository)
        let presenter = AuthPresenter(
            interactor: interactor,
            router: router,
            sessionStore: sessionStore
        )
        return AuthRootView(presenter: presenter)
    }
}
