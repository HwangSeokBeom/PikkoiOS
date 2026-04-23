import Foundation

@MainActor
struct OrderBuilder {
    func build() -> OrderRootView {
        let router = OrderRouter()
        let interactor = OrderInteractor()
        let presenter = OrderPresenter(interactor: interactor, router: router)
        return OrderRootView(presenter: presenter)
    }
}
