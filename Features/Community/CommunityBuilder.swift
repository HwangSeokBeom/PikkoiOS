import Foundation
import SwiftUI

@MainActor
struct CommunityBuilder {
    private let communityRepository: CommunityRepository
    private let locationService: any LocationServiceProtocol
    private let sessionStore: SessionStore
    private let notificationService: AppNotificationService
    private let communityNotificationSnapshotStore: CommunityNotificationSnapshotStore
    private let imageLoader: any AuthorizedImageLoading
    private let makeAuthView: (AuthPresentationContext, @escaping () -> Void) -> AnyView
    private let makeCommunityDetailView: (String) -> AnyView
    private let makeCommunityComposerView: (CommunityComposerMode, CommunityComposerInitialDraft?, @escaping (String) -> Void) -> AnyView
    private let makeCommunitySearchView: (String) -> AnyView
    private let makeStoreDetailView: (String) -> AnyView

    init(
        communityRepository: CommunityRepository,
        locationService: any LocationServiceProtocol,
        sessionStore: SessionStore,
        notificationService: AppNotificationService = NoopAppNotificationService(),
        communityNotificationSnapshotStore: CommunityNotificationSnapshotStore = InMemoryCommunityNotificationSnapshotStore(),
        imageLoader: any AuthorizedImageLoading,
        makeAuthView: @escaping (AuthPresentationContext, @escaping () -> Void) -> AnyView,
        makeCommunityDetailView: @escaping (String) -> AnyView,
        makeCommunityComposerView: @escaping (CommunityComposerMode, CommunityComposerInitialDraft?, @escaping (String) -> Void) -> AnyView,
        makeCommunitySearchView: @escaping (String) -> AnyView,
        makeStoreDetailView: @escaping (String) -> AnyView
    ) {
        self.communityRepository = communityRepository
        self.locationService = locationService
        self.sessionStore = sessionStore
        self.notificationService = notificationService
        self.communityNotificationSnapshotStore = communityNotificationSnapshotStore
        self.imageLoader = imageLoader
        self.makeAuthView = makeAuthView
        self.makeCommunityDetailView = makeCommunityDetailView
        self.makeCommunityComposerView = makeCommunityComposerView
        self.makeCommunitySearchView = makeCommunitySearchView
        self.makeStoreDetailView = makeStoreDetailView
    }

    func build(
        initialQuery: String? = nil,
        routesSearchSubmissions: Bool = true,
        hidesNavigationBar: Bool = true,
        navigationTitle: String? = nil
    ) -> CommunityRootView {
        let router = CommunityRouter()
        let interactor = CommunityInteractor(
            communityRepository: communityRepository,
            locationService: locationService
        )
        let presenter = CommunityPresenter(
            interactor: interactor,
            router: router,
            sessionStore: sessionStore,
            notificationService: notificationService,
            communityNotificationSnapshotStore: communityNotificationSnapshotStore,
            initialQuery: initialQuery,
            routesSearchSubmissions: routesSearchSubmissions
        )

        return CommunityRootView(
            presenter: presenter,
            router: router,
            imageLoader: imageLoader,
            hidesNavigationBar: hidesNavigationBar,
            navigationTitle: navigationTitle,
            makeAuthView: makeAuthView,
            makeCommunityDetailView: makeCommunityDetailView,
            makeCommunityComposerView: makeCommunityComposerView,
            makeCommunitySearchView: makeCommunitySearchView,
            makeStoreDetailView: makeStoreDetailView
        )
    }
}
