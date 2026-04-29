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
    let communityRepository: CommunityRepository
    let chatRepository: ChatRepository
    let chatLocalDataSource: any ChatLocalDataSourceProtocol
    let orderRepository: OrderRepository
    let orderMapper: OrderMapper
    let paymentGateway: any PaymentGateway

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
        let resolvedUserDefaultsStore = userDefaultsStore ?? UserDefaultsStore()
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
        let resolvedChatRepository = DefaultChatRepository(
            remoteDataSource: ChatRemoteDataSource(apiClient: resolvedAPIClient),
            mapper: chatMapper
        )
        let resolvedChatLocalDataSource = CoreDataChatLocalDataSource()
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
        self.communityRepository = resolvedCommunityRepository
        self.chatRepository = resolvedChatRepository
        self.chatLocalDataSource = resolvedChatLocalDataSource
        self.orderRepository = resolvedOrderRepository
        self.orderMapper = orderMapper
        self.paymentGateway = PortOnePaymentGateway()
    }

    func makeAppState() -> AppState {
        let sessionStore = SessionStore(
            tokenStore: tokenStore,
            userDefaultsStore: userDefaultsStore,
            sessionSnapshotStore: sessionSnapshotStore
        )
        let cartStore = CartStore(cartRepository: cartRepository)
        return AppState(sessionStore: sessionStore, cartStore: cartStore)
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
}
