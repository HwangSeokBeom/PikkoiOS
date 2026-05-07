import SwiftUI

@MainActor
struct FeatureBuilderFactory {
    private let container: AppDIContainer
    private let appState: AppState
    private static var inFlightDeviceTokenRegistrationKeys = Set<String>()

    init(container: AppDIContainer, appState: AppState) {
        self.container = container
        self.appState = appState
    }

    func makeAuthView(
        context: AuthPresentationContext = .generic,
        onAuthenticated: @escaping () -> Void = {}
    ) -> AuthRootView {
        AuthBuilder(
            authRepository: container.authRepository,
            socialAuthService: container.socialAuthService,
            appConfiguration: container.appConfiguration,
            sessionStore: appState.sessionStore,
            presentationContext: context,
            onAuthenticated: onAuthenticated
        ).build()
    }

    func makeHomeView(resetTrigger: Int = 0) -> HomeRootView {
        HomeBuilder(
            storeRepository: container.storeRepository,
            bannerRepository: container.bannerRepository,
            notificationService: container.appNotificationService,
            locationService: container.locationService,
            reverseGeocoder: container.reverseGeocoder,
            sessionStore: appState.sessionStore,
            imageLoader: container.authorizedImageLoader,
            makeStoreDetailView: { storeID in
                makeStoreDetailView(storeID: storeID)
            },
            makeStoreSearchView: { query in
                AnyView(makeStoreSearchView(query: query))
            },
            makeBannerWebView: { banner in
                AnyView(makeBannerWebView(banner: banner))
            },
            makeNotificationListView: {
                AnyView(makeNotificationListView())
            },
            makeCartView: {
                makeCartView()
            },
            makeAuthView: {
                AnyView(makeAuthView(context: .protectedResource))
            }
        ).build(resetTrigger: resetTrigger)
    }

    func makeVideoListView(resetTrigger: Int = 0) -> VideoListRootView {
        VideoListBuilder(
            videoRepository: container.videoRepository,
            sessionStore: appState.sessionStore,
            imageLoader: container.authorizedImageLoader,
            appConfiguration: container.appConfiguration,
            tokenStore: container.tokenStore,
            makeVideoPlayerView: { video, onVideoUpdated in
                AnyView(makeVideoPlayerView(video: video, onVideoUpdated: onVideoUpdated))
            }
        ).build(resetTrigger: resetTrigger)
    }

    func makeStoreDetailView(storeID: String = "mock-store") -> StoreDetailRootView {
        StoreDetailBuilder(
            storeID: storeID,
            storeRepository: container.storeRepository,
            reviewRepository: container.reviewRepository,
            orderRepository: container.orderRepository,
            cartStore: appState.cartStore,
            locationService: container.locationService,
            mapLauncher: container.mapLauncher,
            imageLoader: container.authorizedImageLoader,
            makeAuthView: {
                AnyView(makeAuthView(context: .protectedResource))
            },
            makeCartView: { _ in
                makeCartView()
            },
            makeChatView: { target in
                makeChatView(target: target)
            },
            makeReviewComposerView: { context, onSubmitted in
                AnyView(makeReviewComposerView(context: context, onSubmitted: onSubmitted))
            }
        ).build()
    }

    func makeCartView() -> CartRootView {
        CartBuilder(
            cartStore: appState.cartStore,
            imageLoader: container.authorizedImageLoader,
            makeCheckoutView: { draft in
                makeCheckoutView(draft: draft)
            }
        ).build()
    }

    func makeCheckoutView(draft: CheckoutDraft = .empty) -> CheckoutRootView {
        CheckoutBuilder(
            draft: draft,
            orderRepository: container.orderRepository,
            cartStore: appState.cartStore,
            appConfiguration: container.appConfiguration,
            sessionStore: appState.sessionStore,
            makeAuthView: {
                AnyView(makeAuthView(context: .checkout))
            },
            makeOrderView: { orderID in
                makeOrderView(orderID: orderID)
            },
            makePaymentBridgeView: { context, onResult in
                AnyView(
                    makeCheckoutPaymentBridgeView(
                        context: context,
                        onResult: onResult
                    )
                )
            },
            onOrderHistoryRoute: { orderID in
                appState.pendingHighlightedOrderID = orderID
                appState.selectedTab = .order
            }
        ).build()
    }

    func makeOrderView(orderID: String? = nil) -> OrderRootView {
        OrderBuilder(
            initialOrderID: orderID ?? appState.pendingHighlightedOrderID,
            orderRepository: container.orderRepository,
            sessionStore: appState.sessionStore,
            notificationService: container.appNotificationService,
            orderStatusSnapshotStore: container.orderStatusSnapshotStore,
            imageLoader: container.authorizedImageLoader,
            makeAuthView: {
                AnyView(makeAuthView(context: .orderHistory))
            },
            makeOrderDetailView: { orderID in
                AnyView(makeOrderDetailView(orderID: orderID))
            },
            makeCartView: {
                makeCartView()
            },
            onExploreHome: {
                appState.selectedTab = .home
            }
        ).build()
    }

    func makeOrderDetailView(orderID: String) -> OrderDetailRootView {
        OrderDetailBuilder(
            orderID: orderID,
            orderRepository: container.orderRepository,
            sessionStore: appState.sessionStore,
            imageLoader: container.authorizedImageLoader,
            mapper: container.orderMapper,
            makeAuthView: {
                AnyView(makeAuthView(context: .orderHistory))
            },
            makeStoreDetailView: { storeID in
                AnyView(makeStoreDetailView(storeID: storeID))
            },
            makeReviewComposerView: { context, onSubmitted in
                AnyView(makeReviewComposerView(context: context, onSubmitted: onSubmitted))
            }
        ).build()
    }

    func makeProfileView() -> ProfileRootView {
        ProfileBuilder(
            sessionStore: appState.sessionStore,
            authRepository: container.authRepository,
            imageLoader: container.authorizedImageLoader,
            makeLikedStoresView: {
                AnyView(makeLikedStoresView())
            },
            makeMyPostsView: { userID in
                AnyView(makeMyCommunityPostsView(userID: userID))
            },
            makeLikedPostsView: {
                AnyView(makeLikedCommunityPostsView())
            },
            makeMyReviewsView: { userID in
                AnyView(makeMyReviewsView(userID: userID))
            },
            makeChatListView: {
                AnyView(makeChatView())
            },
            makeNotificationListView: {
                AnyView(makeNotificationListView())
            },
            makeUserSearchView: {
                AnyView(makeUserSearchView())
            },
            makeDeveloperDiagnosticsView: {
                AnyView(makeDeveloperDiagnosticsView())
            },
            initialUnreadNotificationCount: container.appNotificationService.unreadCount()
        ).build()
    }

    func syncCurrentDeviceTokenIfNeeded(source: String = "deviceTokenSyncStateChanged") async {
        guard appState.sessionStore.isAuthenticated else {
            let tokenLength = appState.sessionStore.deviceToken?.count ?? 0
            Logger(category: "FCM").warning("[FCM] server register deferred reason=unauthenticated tokenLength=\(tokenLength) source=\(source)")
            Logger(category: "PushToken").debug("[PushToken] sync skipped reason=noUser")
            return
        }

        guard let accessToken = appState.sessionStore.accessToken?.trimmingCharacters(in: .whitespacesAndNewlines),
              !accessToken.isEmpty else {
            Logger(category: "PushToken").debug("[PushToken] sync skipped reason=noAccessToken")
            return
        }

        guard let deviceToken = appState.sessionStore.deviceToken?.trimmingCharacters(in: .whitespacesAndNewlines),
              !deviceToken.isEmpty else {
            Logger(category: "PushToken").debug("[PushToken] sync skipped reason=noFCMToken")
            return
        }

        let userID = appState.sessionStore.currentUserID ?? "unknown"
        guard !appState.sessionStore.hasSyncedCurrentDeviceToken else {
            Logger(category: "FCM").info("[FCM] server register skipped reason=unchangedAndPreviouslyRegistered userId=\(userID) source=\(source)")
            Logger(category: "PushToken").debug("[PushToken] sync skipped reason=sameTokenAlreadySynced")
            return
        }

        let registrationKey = "\(userID)|\(deviceToken)"
        guard Self.inFlightDeviceTokenRegistrationKeys.insert(registrationKey).inserted else {
            Logger(category: "FCM").debug("[FCM] server register deduped key=userId:\(userID):tokenLength:\(deviceToken.count) source=\(source)")
            Logger(category: "PushToken").debug("[PushToken] sync skipped reason=sameTokenInFlight")
            return
        }
        defer {
            Self.inFlightDeviceTokenRegistrationKeys.remove(registrationKey)
        }

        do {
            Logger(category: "FCM").info("[FCM] server register start source=\(source) userId=\(userID) tokenLength=\(deviceToken.count)")
            Logger(category: "PushToken").debug("[PushToken] sync request path=/v1/users/deviceToken userIdExists=\(!userID.isEmpty) tokenLength=\(deviceToken.count)")
            try await container.authRepository.updateDeviceToken(deviceToken)
            appState.sessionStore.markCurrentDeviceTokenSynced()
            Logger(category: "FCM").info("[FCM] server register success source=\(source) userId=\(userID) endpoint=/v1/users/deviceToken")
            Logger(category: "PushToken").debug("[PushToken] sync success userId=\(userID) tokenHash=\(String(deviceToken.hashValue))")
        } catch let error as NetworkError {
            if case .configuration(let configurationError) = error {
                Logger(category: "FCM").error("[FCM] server register failed source=\(source) userId=\(userID) error=\(configurationError.userMessage)")
            } else {
                Logger(category: "FCM").error("[FCM] server register failed source=\(source) userId=\(userID) error=\(error.localizedDescription)")
            }
            Logger(category: "PushToken").error("[PushToken] sync failed status=\(pushTokenStatusDescription(from: error)) message=\(error.localizedDescription) retryable=\(error.isRetryablePushTokenSyncFailure)")
        } catch {
            Logger(category: "FCM").error("[FCM] server register failed source=\(source) userId=\(userID) error=\(error.localizedDescription)")
            Logger(category: "PushToken").error("[PushToken] sync failed status=none message=\(error.localizedDescription) retryable=true")
        }
    }

    private func pushTokenStatusDescription(from error: NetworkError) -> String {
        switch error {
        case .invalidRequest:
            return "400"
        case .unauthorized, .authenticationFailed:
            return "401"
        case .forbidden:
            return "403"
        case .accessTokenExpired:
            return "419"
        case .refreshTokenExpired:
            return "418"
        case .rateLimited:
            return "429"
        case .server:
            return "5xx"
        case .abnormalRequest, .businessAuthorization, .configuration, .conflict, .decoding, .notFound, .transport:
            return "unknown"
        }
    }

    func routePendingNotificationIfNeeded() {
        container.appNotificationRouter.routePendingIfNeeded()
    }

    func setNotificationNavigationReady(_ isReady: Bool) {
        container.appNotificationRouter.setNavigationReady(isReady)
    }

    func makeCommunityView() -> CommunityRootView {
        CommunityBuilder(
            communityRepository: container.communityRepository,
            locationService: container.locationService,
            sessionStore: appState.sessionStore,
            notificationService: container.appNotificationService,
            communityNotificationSnapshotStore: container.communityNotificationSnapshotStore,
            imageLoader: container.authorizedImageLoader,
            makeAuthView: { context, onAuthenticated in
                AnyView(
                    makeAuthView(
                        context: context,
                        onAuthenticated: onAuthenticated
                    )
                )
            },
            makeCommunityDetailView: { postID in
                AnyView(makeCommunityDetailView(postID: postID))
            },
            makeCommunityComposerView: { mode, initialDraft, onSubmittedPost in
                AnyView(makeCommunityComposerView(mode: mode, initialDraft: initialDraft, onSubmittedPost: onSubmittedPost))
            },
            makeCommunitySearchView: { query in
                AnyView(makeCommunitySearchView(query: query))
            },
            makeStoreDetailView: { storeID in
                AnyView(makeStoreDetailView(storeID: storeID))
            }
        ).build()
    }

    func makeCommunityDetailView(postID: String, initialCommentID: String? = nil) -> CommunityDetailRootView {
        CommunityDetailBuilder(
            postID: postID,
            initialCommentID: initialCommentID,
            communityRepository: container.communityRepository,
            locationService: container.locationService,
            sessionStore: appState.sessionStore,
            notificationService: container.appNotificationService,
            communityNotificationSnapshotStore: container.communityNotificationSnapshotStore,
            activeCommunityPostTracker: container.activeCommunityPostTracker,
            imageLoader: container.authorizedImageLoader,
            makeAuthView: { context, onAuthenticated in
                AnyView(
                    makeAuthView(
                        context: context,
                        onAuthenticated: onAuthenticated
                    )
                )
            },
            makeCommunityComposerView: { mode, initialDraft, onSubmittedPost in
                AnyView(makeCommunityComposerView(mode: mode, initialDraft: initialDraft, onSubmittedPost: onSubmittedPost))
            },
            makeStoreDetailView: { storeID in
                AnyView(makeStoreDetailView(storeID: storeID))
            },
            makeChatView: { target in
                AnyView(makeChatView(target: target))
            }
        ).build()
    }

    func makeCommunityComposerView(
        mode: CommunityComposerMode = .create,
        initialDraft: CommunityComposerInitialDraft? = nil,
        onSubmittedPost: @escaping (String) -> Void = { _ in }
    ) -> CommunityComposerRootView {
        CommunityComposerBuilder(
            mode: mode,
            initialDraft: initialDraft,
            communityRepository: container.communityRepository,
            locationService: container.locationService
        ).build(onSubmittedPost: onSubmittedPost)
    }

    func makeReviewComposerView(
        context: ReviewComposerContext,
        onSubmitted: @escaping (UserStoreReview) -> Void = { _ in }
    ) -> ReviewComposerRootView {
        ReviewComposerBuilder(
            context: context,
            reviewRepository: container.reviewRepository
        ).build(onSubmitted: onSubmitted)
    }

    func makeCommunitySearchView(query: String) -> CommunityRootView {
        CommunityBuilder(
            communityRepository: container.communityRepository,
            locationService: container.locationService,
            sessionStore: appState.sessionStore,
            notificationService: container.appNotificationService,
            communityNotificationSnapshotStore: container.communityNotificationSnapshotStore,
            imageLoader: container.authorizedImageLoader,
            makeAuthView: { context, onAuthenticated in
                AnyView(
                    makeAuthView(
                        context: context,
                        onAuthenticated: onAuthenticated
                    )
                )
            },
            makeCommunityDetailView: { postID in
                AnyView(makeCommunityDetailView(postID: postID))
            },
            makeCommunityComposerView: { mode, initialDraft, onSubmittedPost in
                AnyView(makeCommunityComposerView(mode: mode, initialDraft: initialDraft, onSubmittedPost: onSubmittedPost))
            },
            makeCommunitySearchView: { nestedQuery in
                AnyView(makeCommunitySearchView(query: nestedQuery))
            },
            makeStoreDetailView: { storeID in
                AnyView(makeStoreDetailView(storeID: storeID))
            }
        ).build(
            initialQuery: query,
            routesSearchSubmissions: false,
            hidesNavigationBar: false,
            navigationTitle: "검색 결과"
        )
    }

    func makeChatView(
        target: ChatTarget? = nil,
        presentationKind: ChatPresentationKind = .internal
    ) -> ChatRootView {
        ChatBuilder(
            target: target,
            chatRepository: container.chatRepository,
            localDataSource: container.chatLocalDataSource,
            makeRealtimeService: {
                ChatSocketIOClient(
                    configuration: container.appConfiguration,
                    tokenStore: container.tokenStore,
                    mapper: ChatMapper(fileURLResolver: container.authorizedFileURLResolver)
                )
            },
            storeRepository: container.storeRepository,
            sessionStore: appState.sessionStore,
            notificationService: container.appNotificationService,
            activeChatRoomTracker: container.activeChatRoomTracker,
            imageLoader: container.authorizedImageLoader,
            presentationKind: presentationKind
        ).build()
    }

    func makeNotificationListView() -> NotificationListRootView {
        NotificationListBuilder(
            notificationService: container.appNotificationService,
            appNotificationRouter: container.appNotificationRouter
        ).build()
    }

    private func makeVideoPlayerView(
        video: Video,
        onVideoUpdated: @escaping (Video) -> Void
    ) -> VideoPlayerView {
        VideoPlayerBuilder(
            video: video,
            fetchStreamUseCase: FetchVideoStreamUseCase(repository: container.videoRepository),
            setLikeUseCase: SetVideoLikeUseCase(repository: container.videoRepository),
            appConfiguration: container.appConfiguration,
            tokenStore: container.tokenStore,
            onVideoUpdated: onVideoUpdated
        ).build()
    }

    private func makeUserSearchView() -> UserSearchRootView {
        UserSearchBuilder(
            authRepository: container.authRepository,
            sessionStore: appState.sessionStore,
            imageLoader: container.authorizedImageLoader,
            makeChatView: { target in
                AnyView(makeChatView(target: target))
            }
        ).build()
    }

    #if DEBUG
    private func makeDeveloperDiagnosticsView() -> DeveloperDiagnosticsRootView {
        DeveloperDiagnosticsBuilder(
            apiClient: container.apiClient,
            appConfiguration: container.appConfiguration,
            sessionStore: appState.sessionStore,
            authRepository: container.authRepository,
            userDefaultsStore: container.userDefaultsStore,
            notificationService: container.appNotificationService,
            notificationDiagnosticsStore: container.notificationDiagnosticsStore,
            activeChatRoomTracker: container.activeChatRoomTracker,
            activeCommunityPostTracker: container.activeCommunityPostTracker,
            orderStatusSnapshotStore: container.orderStatusSnapshotStore,
            communityNotificationSnapshotStore: container.communityNotificationSnapshotStore,
            imageLoader: container.authorizedImageLoader
        ).build()
    }
    #else
    private func makeDeveloperDiagnosticsView() -> EmptyView {
        EmptyView()
    }
    #endif

    func makeStoreSearchView(query: String) -> StoreListRootView {
        makeStoreListView(mode: .search(query: query))
    }

    func makeLikedStoresView() -> StoreListRootView {
        makeStoreListView(mode: .liked(category: nil))
    }

    private func makeStoreListView(mode: StoreListMode) -> StoreListRootView {
        StoreListBuilder(
            mode: mode,
            storeRepository: container.storeRepository,
            imageLoader: container.authorizedImageLoader,
            makeStoreDetailView: { storeID in
                AnyView(makeStoreDetailView(storeID: storeID))
            }
        ).build()
    }

    private func makeMyCommunityPostsView(userID: String) -> CommunityPostListRootView {
        makeCommunityPostListView(mode: .mine(userID: userID, category: nil))
    }

    private func makeLikedCommunityPostsView() -> CommunityPostListRootView {
        makeCommunityPostListView(mode: .liked(category: nil))
    }

    private func makeCommunityPostListView(mode: CommunityPostListMode) -> CommunityPostListRootView {
        CommunityPostListBuilder(
            mode: mode,
            communityRepository: container.communityRepository,
            imageLoader: container.authorizedImageLoader,
            makeCommunityDetailView: { postID in
                AnyView(makeCommunityDetailView(postID: postID))
            },
            makeStoreDetailView: { storeID in
                AnyView(makeStoreDetailView(storeID: storeID))
            }
        ).build()
    }

    private func makeMyReviewsView(userID: String) -> UserReviewListRootView {
        UserReviewListBuilder(
            userID: userID,
            category: nil,
            reviewRepository: container.reviewRepository,
            imageLoader: container.authorizedImageLoader,
            makeStoreDetailView: { storeID in
                AnyView(makeStoreDetailView(storeID: storeID))
            },
            makeReviewComposerView: { context, onSubmitted in
                AnyView(makeReviewComposerView(context: context, onSubmitted: onSubmitted))
            }
        ).build()
    }

    private func makeBannerWebView(banner: HomeBannerItem) -> some View {
        PikkoWebContentView(
            title: banner.title,
            requestLoader: {
                try await makeWebRequest(
                    path: banner.payloadValue,
                    authorizationPolicy: .accessToken
                )
            }
        )
    }

    private func makeCheckoutPaymentBridgeView(
        context: CheckoutPaymentBridgeContext,
        onResult: @escaping @MainActor (CheckoutPaymentBridgeResult) -> Void
    ) -> some View {
        CheckoutPaymentBridgeView(
            context: context,
            paymentGateway: container.paymentGateway,
            onResult: onResult
        )
    }

    private func makeWebRequest(
        path: String,
        authorizationPolicy: AuthorizationPolicy
    ) async throws -> URLRequest {
        let trimmedPath = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPath.isEmpty else {
            throw NetworkError.invalidRequest
        }

        if let absoluteURL = URL(string: trimmedPath),
           let scheme = absoluteURL.scheme?.lowercased(),
           (scheme == "http" || scheme == "https") {
            let baseHost = container.appConfiguration.baseURL?.host
            if absoluteURL.host == baseHost {
                let endpoint = Endpoint<EmptyResponse>(
                    path: trimmedPath,
                    method: .get,
                    authorizationPolicy: authorizationPolicy
                )
                return try await container.requestBuilder.build(for: endpoint)
            }
            return URLRequest(url: absoluteURL)
        }

        let endpoint = Endpoint<EmptyResponse>(
            path: trimmedPath,
            method: .get,
            authorizationPolicy: authorizationPolicy
        )
        return try await container.requestBuilder.build(for: endpoint)
    }
}

private extension NetworkError {
    var isRetryablePushTokenSyncFailure: Bool {
        switch self {
        case .transport, .server, .rateLimited, .accessTokenExpired:
            return true
        case .invalidRequest, .abnormalRequest, .configuration, .unauthorized, .authenticationFailed,
             .refreshTokenExpired, .forbidden, .notFound, .conflict, .businessAuthorization, .decoding:
            return false
        }
    }
}
