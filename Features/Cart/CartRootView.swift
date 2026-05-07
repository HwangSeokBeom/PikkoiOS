import SwiftUI
import UIKit

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
        .background(PikkoColor.background.ignoresSafeArea())
        .preferredColorScheme(.dark)
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
        .onAppear {
            Self.applyNavigationBarAppearance()
            Logger(category: "CartView").debug("[CartView] backgroundApplied=true navigationAppearance=dark standard=true scrollEdge=true compact=true")
        }
    }

    private static func applyNavigationBarAppearance() {
        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = UIColor(PikkoColor.background)
        appearance.shadowColor = UIColor(PikkoColor.divider)
        appearance.titleTextAttributes = [
            .foregroundColor: UIColor(PikkoColor.primaryText)
        ]
        appearance.largeTitleTextAttributes = [
            .foregroundColor: UIColor(PikkoColor.primaryText)
        ]

        UINavigationBar.appearance().standardAppearance = appearance
        UINavigationBar.appearance().scrollEdgeAppearance = appearance
        UINavigationBar.appearance().compactAppearance = appearance
        UINavigationBar.appearance().tintColor = UIColor(PikkoColor.primary)
    }
}
