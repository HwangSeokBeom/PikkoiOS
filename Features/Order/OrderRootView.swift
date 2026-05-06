import SwiftUI

struct OrderRootView: View {
    @StateObject private var presenter: OrderPresenter
    @StateObject private var router: OrderRouter
    @EnvironmentObject private var sessionStore: SessionStore
    private let imageLoader: any AuthorizedImageLoading
    private let makeAuthView: () -> AnyView
    private let makeOrderDetailView: (String) -> AnyView
    private let makeCartView: () -> CartRootView

    @State private var presentedOrderID: String?
    @State private var isCartPresented = false

    init(
        presenter: OrderPresenter,
        router: OrderRouter,
        imageLoader: any AuthorizedImageLoading,
        makeAuthView: @escaping () -> AnyView,
        makeOrderDetailView: @escaping (String) -> AnyView,
        makeCartView: @escaping () -> CartRootView
    ) {
        _presenter = StateObject(wrappedValue: presenter)
        _router = StateObject(wrappedValue: router)
        self.imageLoader = imageLoader
        self.makeAuthView = makeAuthView
        self.makeOrderDetailView = makeOrderDetailView
        self.makeCartView = makeCartView
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
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isCartPresented = true
                } label: {
                    Image(systemName: "cart")
                        .font(.system(size: 17, weight: .semibold))
                }
                .accessibilityLabel("장바구니")
            }
        }
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
            } else {
                EmptyView()
            }
        }
        .fullScreenCover(isPresented: authPresentedBinding) {
            makeAuthView()
        }
        .sheet(isPresented: $isCartPresented) {
            NavigationStack {
                makeCartView()
            }
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
                    Task { await presenter.send(.refreshRequested) }
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
