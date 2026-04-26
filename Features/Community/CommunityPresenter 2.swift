import Foundation

@MainActor
final class CommunityPresenter: ObservableObject {
    @Published private(set) var viewState = CommunityViewState()

    private let interactor: CommunityInteracting
    private let router: CommunityRouting
    private var hasLoaded = false

    init(interactor: CommunityInteracting, router: CommunityRouting) {
        self.interactor = interactor
        self.router = router
    }

    func send(_ action: CommunityAction) async {
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
