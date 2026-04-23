import Foundation

@MainActor
final class CheckoutPresenter: ObservableObject {
    @Published private(set) var viewState = CheckoutViewState()

    private let interactor: CheckoutInteracting
    private let router: CheckoutRouting
    private var hasLoaded = false

    init(interactor: CheckoutInteracting, router: CheckoutRouting) {
        self.interactor = interactor
        self.router = router
    }

    func send(_ action: CheckoutAction) async {
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
