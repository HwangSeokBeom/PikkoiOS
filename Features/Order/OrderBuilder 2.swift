import Foundation

@MainActor
struct OrderBuilder {
    private let initialOrderID: String?

    init(initialOrderID: String? = nil) {
        self.initialOrderID = initialOrderID
    }

    func build() -> OrderRootView {
        let router = OrderRouter()
        let interactor = OrderInteractor(initialOrderID: initialOrderID)
        let presenter = OrderPresenter(interactor: interactor, router: router)
        return OrderRootView(presenter: presenter)
    }
}
