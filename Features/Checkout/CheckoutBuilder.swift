import Foundation

@MainActor
struct CheckoutBuilder {
    func build() -> CheckoutRootView {
        let router = CheckoutRouter()
        let interactor = CheckoutInteractor()
        let presenter = CheckoutPresenter(interactor: interactor, router: router)
        return CheckoutRootView(presenter: presenter)
    }
}
