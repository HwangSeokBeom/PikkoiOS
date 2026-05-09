import Foundation

@MainActor
final class AppDIContainer {
    let environment: AppEnvironment
    let appConfiguration: AppConfiguration
    let urlSession: URLSession
    let tokenStore: any TokenStore
    let sessionSnapshotStore: any SessionSnapshotStoring
    let userDefaultsStore: any UserDefaultsStoring
    let recentSearchStore: RecentSearchStore
    let requestBuilder: RequestBuilder
    let tokenRefreshCoordinator: TokenRefreshCoordinator
    let apiClient: any APIClientProtocol
    let socialAuthService: any SocialAuthProviding
    let locationService: any LocationServiceProtocol
    let reverseGeocoder: ReverseGeocoder
    let mapLauncher: any MapLauncherProtocol
    let imageCache: ImageCache
    let authorizedFileURLResolver: any AuthorizedFileURLResolving
    let authorizedImageLoader: any AuthorizedImageLoading
    let authRepository: AuthRepository
    let cartRepository: CartRepository
    let storeRepository: StoreRepository
    let reviewRepository: ReviewRepository
    let bannerRepository: BannerRepository
    let videoRepository: VideoRepository
    let communityRepository: CommunityRepository
    let chatRepository: ChatRepository
    let chatLocalDataSource: any ChatLocalDataSourceProtocol
    let chatSendingCoordinator: ChatSendingCoordinator
    let orderRepository: OrderRepository
    let orderMapper: OrderMapper
    let paymentGateway: any PaymentGateway
    let appNotificationRepository: AppNotificationRepository
    let appNotificationService: DefaultAppNotificationService
    let appNotificationRouter: AppNotificationRouter
    let pendingNotificationRouteStore: PendingNotificationRouteStore
    let activeChatRoomTracker: ActiveChatRoomTracker
    let activeCommunityPostTracker: ActiveCommunityPostTracker
    let orderStatusSnapshotStore: OrderStatusSnapshotStore
    let communityNotificationSnapshotStore: CommunityNotificationSnapshotStore
    let notificationDiagnosticsStore: NotificationDiagnosticsStore
    let orderLiveActivityManager: OrderLiveActivityManaging
    let videoLiveActivityManager: VideoLiveActivityManaging
    private(set) var orderBackgroundRefreshCoordinator: OrderBackgroundRefreshing?

    init(
        environment: AppEnvironment = .current,
        appConfiguration: AppConfiguration? = nil,
        urlSession: URLSession? = nil,
        tokenStore: (any TokenStore)? = nil,
        userDefaultsStore: (any UserDefaultsStoring)? = nil,
        locationService: (any LocationServiceProtocol)? = nil,
        mapLauncher: (any MapLauncherProtocol)? = nil,
        socialAuthService: (any SocialAuthProviding)? = nil,
        authRepository: AuthRepository? = nil,
        cartRepository: CartRepository = InMemoryCartRepository()
    ) {
        let resolvedConfiguration = appConfiguration ?? AppConfiguration(environment: environment)
        Self.logStartupNetworkConfiguration(resolvedConfiguration)
        let resolvedUserDefaultsStore = userDefaultsStore ?? UserDefaultsStore()
        let resolvedNotificationRepository = UserDefaultsAppNotificationRepository(store: resolvedUserDefaultsStore)
        let resolvedPendingNotificationRouteStore = PendingNotificationRouteStore()
        let resolvedActiveChatRoomTracker = ActiveChatRoomTracker()
        let resolvedNotificationRouter = AppNotificationRouter(
            pendingRouteStore: resolvedPendingNotificationRouteStore,
            activeChatRoomTracker: resolvedActiveChatRoomTracker
        )
        let resolvedActiveCommunityPostTracker = ActiveCommunityPostTracker()
        let resolvedNotificationDiagnosticsStore = NotificationDiagnosticsStore()
        let resolvedNotificationService = DefaultAppNotificationService(
            repository: resolvedNotificationRepository,
            router: resolvedNotificationRouter,
            activeChatRoomTracker: resolvedActiveChatRoomTracker,
            activeCommunityPostTracker: resolvedActiveCommunityPostTracker,
            diagnosticsStore: resolvedNotificationDiagnosticsStore
        )
        let resolvedOrderStatusSnapshotStore = UserDefaultsOrderStatusSnapshotStore(store: resolvedUserDefaultsStore)
        let resolvedCommunityNotificationSnapshotStore = UserDefaultsCommunityNotificationSnapshotStore(store: resolvedUserDefaultsStore)
        let resolvedTokenStore = tokenStore ?? KeychainTokenStore(
            service: (Bundle.main.bundleIdentifier ?? "com.pikko.ios") + ".tokens"
        )
        let resolvedSessionSnapshotStore = UserDefaultsSessionSnapshotStore(store: resolvedUserDefaultsStore)
        let resolvedRequestBuilder = RequestBuilder(
            configuration: resolvedConfiguration,
            tokenStore: resolvedTokenStore
        )
        let resolvedSession = urlSession ?? URLSession(
            configuration: URLSessionConfigurationFactory.makeDefaultConfiguration()
        )
        let resolvedRefreshCoordinator = TokenRefreshCoordinator(
            session: resolvedSession,
            requestBuilder: resolvedRequestBuilder,
            tokenStore: resolvedTokenStore
        )
        let resolvedAPIClient = APIClient(
            session: resolvedSession,
            requestBuilder: resolvedRequestBuilder,
            tokenRefreshCoordinator: resolvedRefreshCoordinator
        )
        let resolvedSocialAuthService = socialAuthService ?? SocialAuthService(appConfiguration: resolvedConfiguration)
        let resolvedFileURLResolver = AuthorizedFileURLResolver(configuration: resolvedConfiguration)
        let storeMapper = StoreMapper(fileURLResolver: resolvedFileURLResolver)
        let reviewMapper = ReviewMapper(fileURLResolver: resolvedFileURLResolver)
        let bannerMapper = BannerMapper(fileURLResolver: resolvedFileURLResolver)
        let communityMapper = CommunityMapper(fileURLResolver: resolvedFileURLResolver)
        let videoMapper = VideoMapper(fileURLResolver: resolvedFileURLResolver)
        let chatMapper = ChatMapper(fileURLResolver: resolvedFileURLResolver)
        let checkoutMapper = CheckoutMapper()
        let orderMapper = OrderMapper(fileURLResolver: resolvedFileURLResolver)
        let resolvedImageCache = ImageCache()
        let resolvedLocationService = locationService ?? LocationService()
        let resolvedReverseGeocoder = ReverseGeocoder()
        let resolvedMapLauncher = mapLauncher ?? MapLauncher()
        let resolvedStoreRepository = StoreRepositoryImpl(
            remoteDataSource: StoreRemoteDataSource(apiClient: resolvedAPIClient),
            mapper: storeMapper
        )
        let resolvedBannerRepository = BannerRepositoryImpl(
            remoteDataSource: BannerRemoteDataSource(apiClient: resolvedAPIClient),
            mapper: bannerMapper
        )
        let resolvedReviewRepository = ReviewRepositoryImpl(
            remoteDataSource: ReviewRemoteDataSource(apiClient: resolvedAPIClient),
            mapper: reviewMapper
        )
        let resolvedCommunityRepository = CommunityRepositoryImpl(
            remoteDataSource: CommunityRemoteDataSource(apiClient: resolvedAPIClient),
            mapper: communityMapper
        )
        let resolvedVideoRepository = VideoRepositoryImpl(
            remoteDataSource: VideoRemoteDataSource(apiClient: resolvedAPIClient),
            mapper: videoMapper
        )
        let resolvedChatRepository = DefaultChatRepository(
            remoteDataSource: ChatRemoteDataSource(apiClient: resolvedAPIClient),
            mapper: chatMapper
        )
        resolvedNotificationRouter.setChatRouteHydrator(DefaultChatRouteHydrator(chatRepository: resolvedChatRepository))
        let resolvedChatLocalDataSource = CoreDataChatLocalDataSource()
        let resolvedChatSendingCoordinator = ChatSendingCoordinator()
        let resolvedOrderRepository = OrderRepositoryImpl(
            remoteDataSource: OrderRemoteDataSource(apiClient: resolvedAPIClient),
            checkoutMapper: checkoutMapper,
            mapper: orderMapper,
            localSnapshotStore: OrderLocalSnapshotStore(store: resolvedUserDefaultsStore)
        )
        let resolvedAuthRepository = authRepository ?? AuthRepositoryImpl(
            remoteDataSource: AuthRemoteDataSource(apiClient: resolvedAPIClient),
            tokenStore: resolvedTokenStore,
            sessionSnapshotStore: resolvedSessionSnapshotStore,
            fileURLResolver: resolvedFileURLResolver
        )

        self.environment = environment
        self.appConfiguration = resolvedConfiguration
        self.urlSession = resolvedSession
        self.tokenStore = resolvedTokenStore
        self.sessionSnapshotStore = resolvedSessionSnapshotStore
        self.userDefaultsStore = resolvedUserDefaultsStore
        self.recentSearchStore = RecentSearchStore(store: resolvedUserDefaultsStore)
        self.requestBuilder = resolvedRequestBuilder
        self.tokenRefreshCoordinator = resolvedRefreshCoordinator
        self.apiClient = resolvedAPIClient
        self.socialAuthService = resolvedSocialAuthService
        self.locationService = resolvedLocationService
        self.reverseGeocoder = resolvedReverseGeocoder
        self.mapLauncher = resolvedMapLauncher
        self.imageCache = resolvedImageCache
        self.authorizedFileURLResolver = resolvedFileURLResolver
        let remoteAuthorizedImageLoader = AuthorizedImageLoader(
            session: resolvedSession,
            requestBuilder: resolvedRequestBuilder,
            tokenRefreshCoordinator: resolvedRefreshCoordinator,
            fileURLResolver: resolvedFileURLResolver,
            imageCache: resolvedImageCache
        )
        self.authorizedImageLoader = FallbackAuthorizedImageLoader(
            primaryLoader: remoteAuthorizedImageLoader
        )
        self.authRepository = resolvedAuthRepository
        self.cartRepository = cartRepository
        self.storeRepository = resolvedStoreRepository
        self.reviewRepository = resolvedReviewRepository
        self.bannerRepository = resolvedBannerRepository
        self.videoRepository = resolvedVideoRepository
        self.communityRepository = resolvedCommunityRepository
        self.chatRepository = resolvedChatRepository
        self.chatLocalDataSource = resolvedChatLocalDataSource
        self.chatSendingCoordinator = resolvedChatSendingCoordinator
        self.orderRepository = resolvedOrderRepository
        self.orderMapper = orderMapper
        self.paymentGateway = PortOnePaymentGateway()
        self.appNotificationRepository = resolvedNotificationRepository
        self.appNotificationService = resolvedNotificationService
        self.appNotificationRouter = resolvedNotificationRouter
        self.pendingNotificationRouteStore = resolvedPendingNotificationRouteStore
        self.activeChatRoomTracker = resolvedActiveChatRoomTracker
        self.activeCommunityPostTracker = resolvedActiveCommunityPostTracker
        self.orderStatusSnapshotStore = resolvedOrderStatusSnapshotStore
        self.communityNotificationSnapshotStore = resolvedCommunityNotificationSnapshotStore
        self.notificationDiagnosticsStore = resolvedNotificationDiagnosticsStore
        self.orderLiveActivityManager = OrderLiveActivityManager.shared
        self.videoLiveActivityManager = VideoLiveActivityService.shared
    }

    func makeAppState() -> AppState {
        let sessionStore = SessionStore(
            tokenStore: tokenStore,
            userDefaultsStore: userDefaultsStore,
            sessionSnapshotStore: sessionSnapshotStore
        )
        let cartStore = CartStore(cartRepository: cartRepository)
        let appState = AppState(sessionStore: sessionStore, cartStore: cartStore)
        orderBackgroundRefreshCoordinator = OrderBackgroundRefreshCoordinator(
            orderRepository: orderRepository,
            sessionStore: sessionStore,
            liveActivityManager: orderLiveActivityManager
        )
        appNotificationRouter.attach(appState: appState)
        appNotificationService.currentUserIDProvider = { [weak sessionStore] in
            sessionStore?.currentUserID
        }
        return appState
    }

    func makeAppBootstrapper(appState: AppState) -> AppBootstrapper {
        let sessionRestorer = SessionRestorer(
            authRepository: authRepository,
            sessionStore: appState.sessionStore
        )
        return AppBootstrapper(appState: appState, sessionRestorer: sessionRestorer)
    }

    func makeFeatureBuilderFactory(appState: AppState) -> FeatureBuilderFactory {
        FeatureBuilderFactory(container: self, appState: appState)
    }

    private static func logStartupNetworkConfiguration(_ configuration: AppConfiguration) {
#if DEBUG
        let baseURL = configuration.baseURL
        Logger(category: "NetworkConfig").debug(
            "[NetworkConfig] apiBaseURL scheme=\(baseURL?.scheme ?? "nil") host=\(baseURL?.host ?? "nil") port=\(baseURL?.port.map(String.init) ?? "nil") atsExceptionExpected=\(atsExceptionExpected(for: baseURL))"
        )
#endif
    }

#if DEBUG
    private static func atsExceptionExpected(for baseURL: URL?) -> Bool {
        guard baseURL?.host?.caseInsensitiveCompare("pickup.sesac.kr") == .orderedSame else {
            return false
        }

        guard let ats = Bundle.main.object(forInfoDictionaryKey: "NSAppTransportSecurity") as? [String: Any],
              let domains = ats["NSExceptionDomains"] as? [String: Any],
              let pickup = domains["pickup.sesac.kr"] as? [String: Any],
              pickup["NSExceptionAllowsInsecureHTTPLoads"] as? Bool == true else {
            return false
        }

        return true
    }
#endif
}
