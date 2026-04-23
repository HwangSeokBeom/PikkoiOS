import Foundation

@MainActor
final class AppDIContainer {
    let environment: AppEnvironment
    let appConfiguration: AppConfiguration
    let urlSession: URLSession
    let tokenStore: any TokenStore
    let userDefaultsStore: any UserDefaultsStoring
    let recentSearchStore: RecentSearchStore
    let requestBuilder: RequestBuilder
    let tokenRefreshCoordinator: TokenRefreshCoordinator
    let apiClient: any APIClientProtocol
    let locationService: any LocationServiceProtocol
    let reverseGeocoder: ReverseGeocoder
    let mapLauncher: any MapLauncherProtocol
    let imageCache: ImageCache
    let authorizedFileURLResolver: any AuthorizedFileURLResolving
    let authorizedImageLoader: any AuthorizedImageLoading
    let authRepository: AuthRepository
    let cartRepository: CartRepository
    let storeRepository: StoreRepository
    let bannerRepository: BannerRepository

    init(
        environment: AppEnvironment = .current,
        appConfiguration: AppConfiguration? = nil,
        urlSession: URLSession? = nil,
        tokenStore: (any TokenStore)? = nil,
        userDefaultsStore: (any UserDefaultsStoring)? = nil,
        locationService: (any LocationServiceProtocol)? = nil,
        mapLauncher: (any MapLauncherProtocol)? = nil,
        authRepository: AuthRepository = InMemoryAuthRepository(),
        cartRepository: CartRepository = InMemoryCartRepository()
    ) {
        let resolvedConfiguration = appConfiguration ?? AppConfiguration(environment: environment)
        let resolvedUserDefaultsStore = userDefaultsStore ?? UserDefaultsStore()
        let resolvedTokenStore = tokenStore ?? KeychainTokenStore(
            service: (Bundle.main.bundleIdentifier ?? "com.pikko.ios") + ".tokens"
        )
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
        let resolvedFileURLResolver = AuthorizedFileURLResolver(configuration: resolvedConfiguration)
        let storeMapper = StoreMapper(fileURLResolver: resolvedFileURLResolver)
        let bannerMapper = BannerMapper(fileURLResolver: resolvedFileURLResolver)
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

        self.environment = environment
        self.appConfiguration = resolvedConfiguration
        self.urlSession = resolvedSession
        self.tokenStore = resolvedTokenStore
        self.userDefaultsStore = resolvedUserDefaultsStore
        self.recentSearchStore = RecentSearchStore(store: resolvedUserDefaultsStore)
        self.requestBuilder = resolvedRequestBuilder
        self.tokenRefreshCoordinator = resolvedRefreshCoordinator
        self.apiClient = resolvedAPIClient
        self.locationService = resolvedLocationService
        self.reverseGeocoder = resolvedReverseGeocoder
        self.mapLauncher = resolvedMapLauncher
        self.imageCache = resolvedImageCache
        self.authorizedFileURLResolver = resolvedFileURLResolver
        self.authorizedImageLoader = AuthorizedImageLoader(
            session: resolvedSession,
            requestBuilder: resolvedRequestBuilder,
            tokenRefreshCoordinator: resolvedRefreshCoordinator,
            fileURLResolver: resolvedFileURLResolver,
            imageCache: resolvedImageCache
        )
        self.authRepository = authRepository
        self.cartRepository = cartRepository
        self.storeRepository = resolvedStoreRepository
        self.bannerRepository = resolvedBannerRepository
    }

    func makeAppState() -> AppState {
        let sessionStore = SessionStore(
            tokenStore: tokenStore,
            userDefaultsStore: userDefaultsStore
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
