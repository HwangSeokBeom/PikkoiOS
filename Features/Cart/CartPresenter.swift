import Foundation

@MainActor
final class CartPresenter: ObservableObject {
    @Published private(set) var viewState = CartViewState()

    private let interactor: CartInteracting
    private let router: CartRouting

    init(interactor: CartInteracting, router: CartRouting) {
        self.interactor = interactor
        self.router = router
    }

    func send(_ action: CartAction) async {
        switch action {
        case .onAppear:
            viewState = await interactor.loadInitialState()
        case .incrementTapped(let menuID):
            viewState = await interactor.updateQuantity(for: menuID, delta: 1)
        case .decrementTapped(let menuID):
            viewState = await interactor.updateQuantity(for: menuID, delta: -1)
        case .primaryButtonTapped:
            guard viewState.isCheckoutEnabled else { return }
            router.routeToPrimaryDestination()
        }
    }
}
