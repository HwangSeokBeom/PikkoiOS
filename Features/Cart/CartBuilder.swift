import Foundation

@MainActor
struct CartBuilder {
    private let cartStore: CartStore

    init(cartStore: CartStore) {
        self.cartStore = cartStore
    }

    func build() -> CartRootView {
        let router = CartRouter()
        let interactor = CartInteractor(cartStore: cartStore)
        let presenter = CartPresenter(interactor: interactor, router: router)
        return CartRootView(presenter: presenter)
    }
}
