import Foundation
import SwiftUI

@MainActor
struct ProfileBuilder {
    private let sessionStore: SessionStore
    private let authRepository: AuthRepository
    private let imageLoader: any AuthorizedImageLoading
    private let makeLikedStoresView: () -> AnyView
    private let makeMyPostsView: (String) -> AnyView
    private let makeLikedPostsView: () -> AnyView
    private let makeMyReviewsView: (String) -> AnyView
    private let makeChatListView: () -> AnyView
    private let makeNotificationListView: () -> AnyView
    private let makeUserSearchView: () -> AnyView
    private let makeDeveloperDiagnosticsView: () -> AnyView
    private let initialUnreadNotificationCount: Int

    init(
        sessionStore: SessionStore,
        authRepository: AuthRepository,
        imageLoader: any AuthorizedImageLoading,
        makeLikedStoresView: @escaping () -> AnyView,
        makeMyPostsView: @escaping (String) -> AnyView,
        makeLikedPostsView: @escaping () -> AnyView,
        makeMyReviewsView: @escaping (String) -> AnyView,
        makeChatListView: @escaping () -> AnyView,
        makeNotificationListView: @escaping () -> AnyView,
        makeUserSearchView: @escaping () -> AnyView,
        makeDeveloperDiagnosticsView: @escaping () -> AnyView,
        initialUnreadNotificationCount: Int = 0
    ) {
        self.sessionStore = sessionStore
        self.authRepository = authRepository
        self.imageLoader = imageLoader
        self.makeLikedStoresView = makeLikedStoresView
        self.makeMyPostsView = makeMyPostsView
        self.makeLikedPostsView = makeLikedPostsView
        self.makeMyReviewsView = makeMyReviewsView
        self.makeChatListView = makeChatListView
        self.makeNotificationListView = makeNotificationListView
        self.makeUserSearchView = makeUserSearchView
        self.makeDeveloperDiagnosticsView = makeDeveloperDiagnosticsView
        self.initialUnreadNotificationCount = initialUnreadNotificationCount
    }

    func build() -> ProfileRootView {
        let router = ProfileRouter()
        let interactor = ProfileInteractor(
            sessionStore: sessionStore,
            authRepository: authRepository
        )
        let presenter = ProfilePresenter(
            interactor: interactor,
            router: router,
            sessionStore: sessionStore,
            imageLoader: imageLoader
        )
        return ProfileRootView(
            presenter: presenter,
            router: router,
            imageLoader: imageLoader,
            makeLikedStoresView: makeLikedStoresView,
            makeMyPostsView: makeMyPostsView,
            makeLikedPostsView: makeLikedPostsView,
            makeMyReviewsView: makeMyReviewsView,
            makeChatListView: makeChatListView,
            makeNotificationListView: makeNotificationListView,
            makeUserSearchView: makeUserSearchView,
            makeDeveloperDiagnosticsView: makeDeveloperDiagnosticsView,
            initialUnreadNotificationCount: initialUnreadNotificationCount
        )
    }
}
