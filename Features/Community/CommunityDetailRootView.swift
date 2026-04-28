import SwiftUI

struct CommunityDetailRootView: View {
    @StateObject private var presenter: CommunityDetailPresenter
    @StateObject private var router: CommunityDetailRouter
    private let imageLoader: any AuthorizedImageLoading
    private let makeAuthView: (AuthPresentationContext, @escaping () -> Void) -> AnyView
    private let makeCommunityComposerView: (CommunityComposerMode, CommunityComposerInitialDraft?, @escaping (String) -> Void) -> AnyView
    private let makeStoreDetailView: (String) -> AnyView
    private let makeChatView: (ChatTarget) -> AnyView
    @Environment(\.dismiss) private var dismiss

    @State private var presentedStoreID: String?
    @State private var presentedComposerMode: CommunityComposerMode = .create
    @State private var presentedComposerInitialDraft: CommunityComposerInitialDraft?
    @State private var presentedChatTarget: ChatTarget?
    @State private var isComposerPresented = false

    init(
        presenter: CommunityDetailPresenter,
        router: CommunityDetailRouter,
        imageLoader: any AuthorizedImageLoading,
        makeAuthView: @escaping (AuthPresentationContext, @escaping () -> Void) -> AnyView,
        makeCommunityComposerView: @escaping (CommunityComposerMode, CommunityComposerInitialDraft?, @escaping (String) -> Void) -> AnyView,
        makeStoreDetailView: @escaping (String) -> AnyView,
        makeChatView: @escaping (ChatTarget) -> AnyView
    ) {
        _presenter = StateObject(wrappedValue: presenter)
        _router = StateObject(wrappedValue: router)
        self.imageLoader = imageLoader
        self.makeAuthView = makeAuthView
        self.makeCommunityComposerView = makeCommunityComposerView
        self.makeStoreDetailView = makeStoreDetailView
        self.makeChatView = makeChatView
    }

    var body: some View {
        CommunityDetailView(
            presenter: presenter,
            imageLoader: imageLoader,
            onAuthTap: {
                Task { await presenter.send(.loginRequiredTapped) }
            }
        )
        .onChange(of: router.pendingRoute) { _, route in
            switch route {
            case let .storeDetail(storeID):
                presentedStoreID = storeID
            case let .communityComposer(mode, initialDraft):
                presentedComposerMode = mode
                presentedComposerInitialDraft = initialDraft
                isComposerPresented = true
            case let .chat(target):
                presentedChatTarget = target
            default:
                break
            }
        }
        .onChange(of: router.dismissRequested) { _, dismissRequested in
            guard dismissRequested else { return }
            router.clearDismissRequest()
            dismiss()
        }
        .navigationDestination(isPresented: storeDetailPresentedBinding) {
            if let presentedStoreID {
                makeStoreDetailView(presentedStoreID)
            } else {
                EmptyView()
            }
        }
        .navigationDestination(isPresented: composerPresentedBinding) {
            makeCommunityComposerView(
                presentedComposerMode,
                presentedComposerInitialDraft
            ) { postID in
                isComposerPresented = false
                presentedComposerInitialDraft = nil
                presentedComposerMode = .create
                router.clearPendingRoute()
                if postID == presenter.viewState.postID {
                    Task { await presenter.send(.retryTapped) }
                }
            }
        }
        .navigationDestination(isPresented: chatPresentedBinding) {
            if let presentedChatTarget {
                makeChatView(presentedChatTarget)
            } else {
                EmptyView()
            }
        }
        .fullScreenCover(isPresented: authPresentedBinding) {
            makeAuthView(
                router.authPresentationContext,
                {
                    router.completeAuthentication()
                }
            )
        }
        .task {
            await presenter.send(.onAppear)
        }
    }
}

private extension CommunityDetailRootView {
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

    var composerPresentedBinding: Binding<Bool> {
        Binding(
            get: { isComposerPresented },
            set: { isPresented in
                if !isPresented {
                    isComposerPresented = false
                    presentedComposerMode = .create
                    presentedComposerInitialDraft = nil
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
}
