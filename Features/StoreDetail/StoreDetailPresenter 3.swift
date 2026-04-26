import Foundation

@MainActor
final class StoreDetailPresenter: ObservableObject {
    @Published private(set) var viewState = StoreDetailViewState()

    private let interactor: StoreDetailInteracting
    private let router: StoreDetailRouting
    private var hasLoaded = false

    init(interactor: StoreDetailInteracting, router: StoreDetailRouting) {
        self.interactor = interactor
        self.router = router
    }

    func send(_ action: StoreDetailAction) async {
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
