import Foundation

@MainActor
final class CartPresenter: ObservableObject {
    @Published private(set) var viewState = CartViewState()

    private let interactor: CartInteracting
    private let router: CartRouting
    private var hasLoaded = false

    init(interactor: CartInteracting, router: CartRouting) {
        self.interactor = interactor
        self.router = router
    }

    func send(_ action: CartAction) async {
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
