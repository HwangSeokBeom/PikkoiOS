import Foundation

@MainActor
struct ProfileBuilder {
    private let sessionStore: SessionStore

    init(sessionStore: SessionStore) {
        self.sessionStore = sessionStore
    }

    func build() -> ProfileRootView {
        let router = ProfileRouter()
        let interactor = ProfileInteractor(sessionStore: sessionStore)
        let presenter = ProfilePresenter(interactor: interactor, router: router)
        return ProfileRootView(presenter: presenter)
    }
}
