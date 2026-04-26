import Foundation

@MainActor
struct CartBuilder {
    private let cartStore: CartStore
    private let imageLoader: any AuthorizedImageLoading
    private let makeCheckoutView: (CheckoutDraft) -> CheckoutRootView

    init(
        cartStore: CartStore,
        imageLoader: any AuthorizedImageLoading,
        makeCheckoutView: @escaping (CheckoutDraft) -> CheckoutRootView
    ) {
        self.cartStore = cartStore
        self.imageLoader = imageLoader
        self.makeCheckoutView = makeCheckoutView
    }

    func build() -> CartRootView {
        let router = CartRouter()
        let interactor = CartInteractor(cartStore: cartStore)
        let presenter = CartPresenter(interactor: interactor, router: router)
        return CartRootView(
            presenter: presenter,
            router: router,
            imageLoader: imageLoader,
            makeCheckoutView: makeCheckoutView
        )
    }
}
