import Foundation

@MainActor
final class OrderPresenter: ObservableObject {
    @Published private(set) var viewState = OrderViewState()

    private let interactor: OrderInteracting
    private let router: OrderRouting
    private var hasLoaded = false

    init(interactor: OrderInteracting, router: OrderRouting) {
        self.interactor = interactor
        self.router = router
    }

    func send(_ action: OrderAction) async {
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
