import SwiftUI

struct OrderRootView: View {
    @StateObject private var presenter: OrderPresenter
    @StateObject private var router: OrderRouter
    @EnvironmentObject private var sessionStore: SessionStore
    private let imageLoader: any AuthorizedImageLoading
    private let makeAuthView: () -> AnyView
    private let makeOrderDetailView: (String) -> AnyView

    @State private var presentedOrderID: String?

    init(
        presenter: OrderPresenter,
        router: OrderRouter,
        imageLoader: any AuthorizedImageLoading,
        makeAuthView: @escaping () -> AnyView,
        makeOrderDetailView: @escaping (String) -> AnyView
    ) {
        _presenter = StateObject(wrappedValue: presenter)
        _router = StateObject(wrappedValue: router)
        self.imageLoader = imageLoader
        self.makeAuthView = makeAuthView
        self.makeOrderDetailView = makeOrderDetailView
    }

    var body: some View {
        OrderView(
            presenter: presenter,
            imageLoader: imageLoader,
            onAuthTap: {
                Task { await presenter.send(.loginRequiredTapped) }
            },
            onExploreTap: {
                Task { await presenter.send(.exploreStoresTapped) }
            }
        )
        .navigationTitle(presenter.viewState.title)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await presenter.send(.onAppear)
        }
        .onChange(of: sessionStore.isAuthenticated) { previousValue, isAuthenticated in
            guard !previousValue, isAuthenticated else { return }
            Task { await presenter.send(.refreshRequested) }
        }
        .onChange(of: router.pendingRoute) { _, route in
            guard case .some(.orderDetail(let orderID)) = route else { return }
            presentedOrderID = orderID
        }
        .navigationDestination(isPresented: orderDetailPresentedBinding) {
            if let presentedOrderID {
                makeOrderDetailView(presentedOrderID)
            }
        }
        .fullScreenCover(isPresented: authPresentedBinding) {
            makeAuthView()
        }
    }
}

private extension OrderRootView {
    var orderDetailPresentedBinding: Binding<Bool> {
        Binding(
            get: { presentedOrderID != nil },
            set: { isPresented in
                if !isPresented {
                    presentedOrderID = nil
                    router.clearPendingRoute()
                }
            }
        )
    }

    var authPresentedBinding: Binding<Bool> {
        Binding(
            get: { router.isAuthPresented },
            set: { isPresented in
                if !isPresented {
                    router.dismissAuth()
                }
            }
        )
    }
}
