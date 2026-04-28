import SwiftUI

struct OrderDetailRootView: View {
    @StateObject private var presenter: OrderDetailPresenter
    @StateObject private var router: OrderDetailRouter
    @EnvironmentObject private var sessionStore: SessionStore
    private let imageLoader: any AuthorizedImageLoading
    private let makeAuthView: () -> AnyView
    private let makeStoreDetailView: (String) -> AnyView
    private let makeReviewComposerView: (ReviewComposerContext, @escaping (UserStoreReview) -> Void) -> AnyView

    @State private var presentedStoreID: String?
    @State private var presentedReviewContext: ReviewComposerContext?

    init(
        presenter: OrderDetailPresenter,
        router: OrderDetailRouter,
        imageLoader: any AuthorizedImageLoading,
        makeAuthView: @escaping () -> AnyView,
        makeStoreDetailView: @escaping (String) -> AnyView,
        makeReviewComposerView: @escaping (ReviewComposerContext, @escaping (UserStoreReview) -> Void) -> AnyView
    ) {
        _presenter = StateObject(wrappedValue: presenter)
        _router = StateObject(wrappedValue: router)
        self.imageLoader = imageLoader
        self.makeAuthView = makeAuthView
        self.makeStoreDetailView = makeStoreDetailView
        self.makeReviewComposerView = makeReviewComposerView
    }

    var body: some View {
        OrderDetailView(
            presenter: presenter,
            imageLoader: imageLoader,
            onAuthTap: {
                Task { await presenter.send(.loginRequiredTapped) }
            }
        )
        .onChange(of: router.pendingRoute) { _, route in
            switch route {
            case .some(.storeDetail(let storeID)):
                presentedStoreID = storeID
            case .some(.reviewComposer(let context)):
                presentedReviewContext = context
            default:
                break
            }
        }
        .navigationDestination(isPresented: storeDetailPresentedBinding) {
            if let presentedStoreID {
                makeStoreDetailView(presentedStoreID)
            } else {
                EmptyView()
            }
        }
        .navigationDestination(isPresented: reviewComposerPresentedBinding) {
            if let presentedReviewContext {
                makeReviewComposerView(presentedReviewContext) { _ in
                    Task { await presenter.send(.retryTapped) }
                }
            } else {
                EmptyView()
            }
        }
        .onChange(of: sessionStore.isAuthenticated) { previousValue, isAuthenticated in
            guard !previousValue, isAuthenticated else { return }
            Task { await presenter.send(.retryTapped) }
        }
        .fullScreenCover(isPresented: authPresentedBinding) {
            makeAuthView()
        }
        .task {
            await presenter.send(.onAppear)
        }
    }
}

private extension OrderDetailRootView {
    var storeDetailPresentedBinding: Binding<Bool> {
        Binding(
            get: { presentedStoreID != nil },
            set: { isPresented in
                if !isPresented {
                    presentedStoreID = nil
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

    var reviewComposerPresentedBinding: Binding<Bool> {
        Binding(
            get: { presentedReviewContext != nil },
            set: { isPresented in
                if !isPresented {
                    presentedReviewContext = nil
                    router.clearPendingRoute()
                }
            }
        )
    }
}
