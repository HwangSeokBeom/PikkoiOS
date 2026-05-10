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
            clearDismissRequestAfterViewUpdate()
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
                clearPendingRouteAfterViewUpdate()
                if postID == presenter.viewState.postID {
                    Task { await presenter.send(.retryTapped) }
                }
            }
        }
        .navigationDestination(isPresented: replyThreadPresentedBinding) {
            if let replyThread = presenter.viewState.replyThread {
                CommentReplyThreadView(
                    thread: replyThread,
                    sectionState: presenter.viewState.commentSection,
                    imageLoader: imageLoader,
                    onDraftChanged: { draft in
                        Task { await presenter.send(.replyDraftChanged(draft)) }
                    },
                    onSubmitTapped: {
                        Task { await presenter.send(.replySubmitTapped) }
                    },
                    onAuthTapped: {
                        Task { await presenter.send(.loginRequiredTapped) }
                    },
                    onEditTapped: { commentID in
                        Task { await presenter.send(.commentEditTapped(commentID)) }
                    },
                    onEditDraftChanged: { draft in
                        Task { await presenter.send(.commentEditDraftChanged(draft)) }
                    },
                    onEditSaveTapped: {
                        Task { await presenter.send(.commentEditSaveTapped) }
                    },
                    onEditCancelTapped: {
                        Task { await presenter.send(.commentEditCancelled) }
                    },
                    onDeleteConfirmed: { commentID in
                        Task { await presenter.send(.commentDeleteConfirmed(commentID)) }
                    },
                    onBackTapped: {
                        Task { await presenter.send(.replyThreadBackTapped) }
                    },
                    onScrollTargetHandled: {
                        Task { await presenter.send(.replyScrollTargetHandled) }
                    }
                )
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
        .onDisappear {
            Task { await presenter.send(.onDisappear) }
        }
    }
}

private extension CommunityDetailRootView {
    var replyThreadPresentedBinding: Binding<Bool> {
        Binding(
            get: { presenter.viewState.replyThread != nil },
            set: { isPresented in
                guard !isPresented else { return }
                Task { @MainActor in
                    await presenter.send(.replyThreadDismissed)
                }
            }
        )
    }

    var storeDetailPresentedBinding: Binding<Bool> {
        Binding(
            get: { presentedStoreID != nil },
            set: { isPresented in
                if !isPresented {
                    presentedStoreID = nil
                    clearPendingRouteAfterViewUpdate()
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
                    clearPendingRouteAfterViewUpdate()
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
                    clearPendingRouteAfterViewUpdate()
                }
            }
        )
    }

    func clearPendingRouteAfterViewUpdate() {
        Task { @MainActor in
            await Task.yield()
            router.clearPendingRoute()
        }
    }

    func clearDismissRequestAfterViewUpdate() {
        Task { @MainActor in
            await Task.yield()
            router.clearDismissRequest()
        }
    }
}
