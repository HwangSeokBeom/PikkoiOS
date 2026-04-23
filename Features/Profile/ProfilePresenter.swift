import Foundation

@MainActor
final class ProfilePresenter: ObservableObject {
    @Published private(set) var viewState = ProfileViewState()

    private let interactor: ProfileInteracting
    private let router: ProfileRouting
    private var hasLoaded = false

    init(interactor: ProfileInteracting, router: ProfileRouting) {
        self.interactor = interactor
        self.router = router
    }

    func send(_ action: ProfileAction) async {
        switch action {
        case .onAppear:
            guard !hasLoaded else { return }
            hasLoaded = true
            viewState = await interactor.loadInitialState()
        case .primaryButtonTapped:
            router.routeToPrimaryDestination()
        }
    }
}
