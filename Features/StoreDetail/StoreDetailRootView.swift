import SwiftUI

struct StoreDetailRootView: View {
    @StateObject private var presenter: StoreDetailPresenter
    @StateObject private var router: StoreDetailRouter
    private let imageLoader: any AuthorizedImageLoading
    private let makeAuthView: () -> AnyView
    private let makeCartView: (String) -> CartRootView
    private let makeChatView: (ChatTarget) -> ChatRootView
    private let makeReviewComposerView: (ReviewComposerContext, @escaping (UserStoreReview) -> Void) -> AnyView

    @State private var presentedCartStoreID: String?
    @State private var presentedChatTarget: ChatTarget?
    @State private var presentedReviewContext: ReviewComposerContext?

    init(
        presenter: StoreDetailPresenter,
        router: StoreDetailRouter,
        imageLoader: any AuthorizedImageLoading,
        makeAuthView: @escaping () -> AnyView,
        makeCartView: @escaping (String) -> CartRootView,
        makeChatView: @escaping (ChatTarget) -> ChatRootView,
        makeReviewComposerView: @escaping (ReviewComposerContext, @escaping (UserStoreReview) -> Void) -> AnyView
    ) {
        _presenter = StateObject(wrappedValue: presenter)
        _router = StateObject(wrappedValue: router)
        self.imageLoader = imageLoader
        self.makeAuthView = makeAuthView
        self.makeCartView = makeCartView
        self.makeChatView = makeChatView
        self.makeReviewComposerView = makeReviewComposerView
    }

    var body: some View {
        StoreDetailView(
            presenter: presenter,
            imageLoader: imageLoader,
            onAuthTap: {
                Task { await presenter.send(.loginRequiredTapped) }
            }
        )
        .onChange(of: router.pendingRoute) { _, route in
            switch route {
            case .cart(let storeID):
                presentedCartStoreID = storeID
            case .chat(let target):
                presentedChatTarget = target
            case .reviewComposer(let context):
                presentedReviewContext = context
            default:
                break
            }
        }
        .navigationDestination(isPresented: cartPresentedBinding) {
            if let presentedCartStoreID {
                makeCartView(presentedCartStoreID)
            } else {
                EmptyView()
            }
        }
        .navigationDestination(isPresented: chatPresentedBinding) {
            if let presentedChatTarget {
                makeChatView(presentedChatTarget)
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
        .fullScreenCover(isPresented: authPresentedBinding) {
            makeAuthView()
        }
        .task {
            await presenter.send(.onAppear)
        }
    }
}

private extension StoreDetailRootView {
    var cartPresentedBinding: Binding<Bool> {
        Binding(
            get: { presentedCartStoreID != nil },
            set: { isPresented in
                if !isPresented {
                    presentedCartStoreID = nil
                    router.clearPendingRoute()
                }
            }
        )
    }

    var chatPresentedBinding: Binding<Bool> {
        Binding(
            get: { presentedChatTarget != nil },
            set: { isPresented in
                if !isPresented {
                    presentedChatTarget = nil
                    router.clearPendingRoute()
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
