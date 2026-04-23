import Foundation

@MainActor
final class AuthPresenter: ObservableObject {
    @Published private(set) var viewState = AuthViewState()

    private let interactor: AuthInteracting
    private let router: AuthRouting
    private let sessionStore: SessionStore
    private var hasLoaded = false

    init(
        interactor: AuthInteracting,
        router: AuthRouting,
        sessionStore: SessionStore
    ) {
        self.interactor = interactor
        self.router = router
        self.sessionStore = sessionStore
    }

    func send(_ action: AuthAction) async {
        switch action {
        case .onAppear:
            guard !hasLoaded else { return }
            hasLoaded = true
            viewState = await interactor.loadInitialState()
        case .primaryButtonTapped:
            viewState.isLoading = true
            do {
                let session = try await interactor.signInStub()
                sessionStore.apply(session: session)
                router.routeToPostAuthHome()
            } catch {
                Logger.shared.warning("Stub sign-in failed: \(error.localizedDescription)")
            }
            viewState.isLoading = false
        }
    }
}
