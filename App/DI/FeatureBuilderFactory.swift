import SwiftUI

@MainActor
struct FeatureBuilderFactory {
    private let container: AppDIContainer
    private let appState: AppState

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
            makeAuthView: {
                AnyView(makeAuthView(context: .protectedResource))
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
            makeChatView: { storeID in
                makeChatView(storeID: storeID)
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
            imageLoader: container.authorizedImageLoader,
            makeAuthView: {
                AnyView(makeAuthView(context: .orderHistory))
            },
            makeOrderDetailView: { orderID in
                AnyView(makeOrderDetailView(orderID: orderID))
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
            }
        ).build()
    }

    func syncCurrentDeviceTokenIfNeeded() async {
        guard appState.sessionStore.isAuthenticated,
              let deviceToken = appState.sessionStore.deviceToken?.trimmingCharacters(in: .whitespacesAndNewlines),
              !deviceToken.isEmpty else {
            return
        }

        guard !appState.sessionStore.hasSyncedCurrentDeviceToken else { return }

        do {
            try await container.authRepository.updateDeviceToken(deviceToken)
            appState.sessionStore.markCurrentDeviceTokenSynced()
        } catch let error as NetworkError {
            if case .configuration(let configurationError) = error {
                Logger.shared.warning("Device token sync skipped due to configuration issue: \(configurationError.userMessage)")
            } else {
                Logger.shared.debug("Device token sync failed but authentication will continue: \(error.localizedDescription)")
            }
        } catch {
            Logger.shared.debug("Device token sync failed but authentication will continue: \(error.localizedDescription)")
        }
    }

    func makeCommunityView() -> CommunityRootView {
        CommunityBuilder(
            communityRepository: container.communityRepository,
            locationService: container.locationService,
            sessionStore: appState.sessionStore,
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

    func makeCommunityDetailView(postID: String) -> CommunityDetailRootView {
        CommunityDetailBuilder(
            postID: postID,
            communityRepository: container.communityRepository,
            locationService: container.locationService,
            sessionStore: appState.sessionStore,
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

    func makeChatView(storeID: String? = nil) -> ChatRootView {
        ChatBuilder(storeID: storeID).build()
    }

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
            requestLoader: {
                try await makeWebRequest(
                    path: context.initialURL.absoluteString,
                    authorizationPolicy: .none
                )
            },
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
