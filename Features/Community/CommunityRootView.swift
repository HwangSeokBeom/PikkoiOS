import SwiftUI

struct CommunityRootView: View {
    @StateObject private var presenter: CommunityPresenter
    @StateObject private var router: CommunityRouter
    private let imageLoader: any AuthorizedImageLoading
    private let hidesNavigationBar: Bool
    private let navigationTitle: String?
    private let makeAuthView: (AuthPresentationContext, @escaping () -> Void) -> AnyView
    private let makeCommunityDetailView: (String) -> AnyView
    private let makeCommunityComposerView: (CommunityComposerMode, CommunityComposerInitialDraft?, @escaping (String) -> Void) -> AnyView
    private let makeCommunitySearchView: (String) -> AnyView
    private let makeStoreDetailView: (String) -> AnyView

    @State private var presentedPostID: String?
    @State private var presentedSearchQuery: String?
    @State private var presentedStoreID: String?
    @State private var presentedComposerMode: CommunityComposerMode = .create
    @State private var presentedComposerInitialDraft: CommunityComposerInitialDraft?
    @State private var isComposerPresented = false

    init(
        presenter: CommunityPresenter,
        router: CommunityRouter,
        imageLoader: any AuthorizedImageLoading,
        hidesNavigationBar: Bool,
        navigationTitle: String?,
        makeAuthView: @escaping (AuthPresentationContext, @escaping () -> Void) -> AnyView,
        makeCommunityDetailView: @escaping (String) -> AnyView,
        makeCommunityComposerView: @escaping (CommunityComposerMode, CommunityComposerInitialDraft?, @escaping (String) -> Void) -> AnyView,
        makeCommunitySearchView: @escaping (String) -> AnyView,
        makeStoreDetailView: @escaping (String) -> AnyView
    ) {
        _presenter = StateObject(wrappedValue: presenter)
        _router = StateObject(wrappedValue: router)
        self.imageLoader = imageLoader
        self.hidesNavigationBar = hidesNavigationBar
        self.navigationTitle = navigationTitle
        self.makeAuthView = makeAuthView
        self.makeCommunityDetailView = makeCommunityDetailView
        self.makeCommunityComposerView = makeCommunityComposerView
        self.makeCommunitySearchView = makeCommunitySearchView
        self.makeStoreDetailView = makeStoreDetailView
    }

    var body: some View {
        CommunityView(
            presenter: presenter,
            imageLoader: imageLoader,
            onAuthTap: {
                Task { await presenter.send(.loginRequiredTapped) }
            }
        )
        .applyCommunityNavigationStyle(
            hidesNavigationBar: hidesNavigationBar,
            navigationTitle: navigationTitle
        )
        .task {
            await presenter.send(.onAppear)
        }
        .onReceive(NotificationCenter.default.publisher(for: .pikkoSelectedLocationDidChange)) { _ in
            Task { await presenter.send(.refreshRequested) }
        }
        .onChange(of: router.pendingRoute) { _, route in
            switch route {
            case .storeDetail(let storeID):
                presentedStoreID = storeID
            case .communityDetail(let postID):
                presentedPostID = postID
            case .communitySearch(let query):
                presentedSearchQuery = query
            case let .communityComposer(mode, initialDraft):
                presentedComposerMode = mode
                presentedComposerInitialDraft = initialDraft
                isComposerPresented = true
            default:
                break
            }
        }
        .navigationDestination(isPresented: communityDetailPresentedBinding) {
            if let presentedPostID {
                makeCommunityDetailView(presentedPostID)
            }
        }
        .navigationDestination(isPresented: storeDetailPresentedBinding) {
            if let presentedStoreID {
                makeStoreDetailView(presentedStoreID)
            }
        }
        .navigationDestination(isPresented: communitySearchPresentedBinding) {
            if let presentedSearchQuery {
                makeCommunitySearchView(presentedSearchQuery)
            }
        }
        .navigationDestination(isPresented: communityComposerPresentedBinding) {
            makeCommunityComposerView(
                presentedComposerMode,
                presentedComposerInitialDraft
            ) { postID in
                isComposerPresented = false
                presentedComposerInitialDraft = nil
                presentedComposerMode = .create
                router.clearPendingRoute()
                Task { @MainActor in
                    await presenter.send(.postSubmitted(postID))
                    presentedPostID = postID
                }
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
    }
}

private extension CommunityRootView {
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

    var communityDetailPresentedBinding: Binding<Bool> {
        Binding(
            get: { presentedPostID != nil },
            set: { isPresented in
                if !isPresented {
                    let dismissedPostID = presentedPostID
                    presentedPostID = nil
                    router.clearPendingRoute()
                    guard presenter.shouldRefreshAfterDetailDismiss(postID: dismissedPostID) else {
                        return
                    }
                    Task { await presenter.send(.refreshRequested) }
                }
            }
        )
    }

    var communitySearchPresentedBinding: Binding<Bool> {
        Binding(
            get: { presentedSearchQuery != nil },
            set: { isPresented in
                if !isPresented {
                    presentedSearchQuery = nil
                    router.clearPendingRoute()
                }
            }
        )
    }

    var communityComposerPresentedBinding: Binding<Bool> {
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

private struct CommunityNavigationStyleModifier: ViewModifier {
    let hidesNavigationBar: Bool
    let navigationTitle: String?

    func body(content: Content) -> some View {
        if hidesNavigationBar {
            content.toolbar(.hidden, for: .navigationBar)
        } else {
            content
                .navigationTitle(navigationTitle ?? "커뮤니티")
                .navigationBarTitleDisplayMode(.inline)
        }
    }
}

private extension View {
    func applyCommunityNavigationStyle(
        hidesNavigationBar: Bool,
        navigationTitle: String?
    ) -> some View {
        modifier(
            CommunityNavigationStyleModifier(
                hidesNavigationBar: hidesNavigationBar,
                navigationTitle: navigationTitle
            )
        )
    }
}
