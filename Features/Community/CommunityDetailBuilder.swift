import SwiftUI

@MainActor
struct CommunityDetailBuilder {
    private let postID: String
    private let communityRepository: CommunityRepository
    private let locationService: any LocationServiceProtocol
    private let sessionStore: SessionStore
    private let imageLoader: any AuthorizedImageLoading
    private let makeAuthView: (AuthPresentationContext, @escaping () -> Void) -> AnyView
    private let makeCommunityComposerView: (CommunityComposerMode, CommunityComposerInitialDraft?, @escaping (String) -> Void) -> AnyView
    private let makeStoreDetailView: (String) -> AnyView
    private let makeChatView: (ChatTarget) -> AnyView

    init(
        postID: String,
        communityRepository: CommunityRepository,
        locationService: any LocationServiceProtocol,
        sessionStore: SessionStore,
        imageLoader: any AuthorizedImageLoading,
        makeAuthView: @escaping (AuthPresentationContext, @escaping () -> Void) -> AnyView,
        makeCommunityComposerView: @escaping (CommunityComposerMode, CommunityComposerInitialDraft?, @escaping (String) -> Void) -> AnyView,
        makeStoreDetailView: @escaping (String) -> AnyView,
        makeChatView: @escaping (ChatTarget) -> AnyView
    ) {
        self.postID = postID
        self.communityRepository = communityRepository
        self.locationService = locationService
        self.sessionStore = sessionStore
        self.imageLoader = imageLoader
        self.makeAuthView = makeAuthView
        self.makeCommunityComposerView = makeCommunityComposerView
        self.makeStoreDetailView = makeStoreDetailView
        self.makeChatView = makeChatView
    }

    func build() -> CommunityDetailRootView {
        let router = CommunityDetailRouter()
        let interactor = CommunityDetailInteractor(
            postID: postID,
            communityRepository: communityRepository,
            locationService: locationService,
            sessionStore: sessionStore
        )
        let presenter = CommunityDetailPresenter(
            postID: postID,
            interactor: interactor,
            router: router,
            sessionStore: sessionStore
        )

        return CommunityDetailRootView(
            presenter: presenter,
            router: router,
            imageLoader: imageLoader,
            makeAuthView: makeAuthView,
            makeCommunityComposerView: makeCommunityComposerView,
            makeStoreDetailView: makeStoreDetailView,
            makeChatView: makeChatView
        )
    }
}
