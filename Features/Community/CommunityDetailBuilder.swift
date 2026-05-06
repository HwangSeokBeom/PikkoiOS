import SwiftUI

@MainActor
struct CommunityDetailBuilder {
    private let postID: String
    private let initialCommentID: String?
    private let communityRepository: CommunityRepository
    private let locationService: any LocationServiceProtocol
    private let sessionStore: SessionStore
    private let notificationService: AppNotificationService
    private let communityNotificationSnapshotStore: CommunityNotificationSnapshotStore
    private let activeCommunityPostTracker: ActiveCommunityPostTracking
    private let imageLoader: any AuthorizedImageLoading
    private let makeAuthView: (AuthPresentationContext, @escaping () -> Void) -> AnyView
    private let makeCommunityComposerView: (CommunityComposerMode, CommunityComposerInitialDraft?, @escaping (String) -> Void) -> AnyView
    private let makeStoreDetailView: (String) -> AnyView
    private let makeChatView: (ChatTarget) -> AnyView

    init(
        postID: String,
        initialCommentID: String? = nil,
        communityRepository: CommunityRepository,
        locationService: any LocationServiceProtocol,
        sessionStore: SessionStore,
        notificationService: AppNotificationService = NoopAppNotificationService(),
        communityNotificationSnapshotStore: CommunityNotificationSnapshotStore = InMemoryCommunityNotificationSnapshotStore(),
        activeCommunityPostTracker: ActiveCommunityPostTracking = ActiveCommunityPostTracker(),
        imageLoader: any AuthorizedImageLoading,
        makeAuthView: @escaping (AuthPresentationContext, @escaping () -> Void) -> AnyView,
        makeCommunityComposerView: @escaping (CommunityComposerMode, CommunityComposerInitialDraft?, @escaping (String) -> Void) -> AnyView,
        makeStoreDetailView: @escaping (String) -> AnyView,
        makeChatView: @escaping (ChatTarget) -> AnyView
    ) {
        self.postID = postID
        self.initialCommentID = initialCommentID
        self.communityRepository = communityRepository
        self.locationService = locationService
        self.sessionStore = sessionStore
        self.notificationService = notificationService
        self.communityNotificationSnapshotStore = communityNotificationSnapshotStore
        self.activeCommunityPostTracker = activeCommunityPostTracker
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
            initialCommentID: initialCommentID,
            interactor: interactor,
            router: router,
            sessionStore: sessionStore,
            notificationService: notificationService,
            communityNotificationSnapshotStore: communityNotificationSnapshotStore,
            activeCommunityPostTracker: activeCommunityPostTracker
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
