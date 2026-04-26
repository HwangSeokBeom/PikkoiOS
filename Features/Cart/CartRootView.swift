import SwiftUI

struct CartRootView: View {
    @StateObject private var presenter: CartPresenter
    @StateObject private var router: CartRouter
    private let imageLoader: any AuthorizedImageLoading
    private let makeCheckoutView: (CheckoutDraft) -> CheckoutRootView

    init(
        presenter: CartPresenter,
        router: CartRouter,
        imageLoader: any AuthorizedImageLoading,
        makeCheckoutView: @escaping (CheckoutDraft) -> CheckoutRootView
    ) {
        _presenter = StateObject(wrappedValue: presenter)
        _router = StateObject(wrappedValue: router)
        self.imageLoader = imageLoader
        self.makeCheckoutView = makeCheckoutView
    }

    var body: some View {
        CartView(
            presenter: presenter,
            imageLoader: imageLoader
        )
        .navigationDestination(
            isPresented: Binding(
                get: { router.pendingRoute == .checkout },
                set: { isPresented in
                    if !isPresented {
                        router.clearPendingRoute()
                    }
                }
            )
        ) {
            makeCheckoutView(presenter.viewState.checkoutDraft)
        }
        .task {
            await presenter.send(.onAppear)
        }
    }
}
