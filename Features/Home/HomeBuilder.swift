import Foundation
import SwiftUI

@MainActor
struct HomeBuilder {
    private let storeRepository: StoreRepository
    private let bannerRepository: BannerRepository
    private let notificationService: AppNotificationService
    private let locationService: any LocationServiceProtocol
    private let reverseGeocoder: ReverseGeocoder
    private let sessionStore: SessionStore
    private let imageLoader: any AuthorizedImageLoading
    private let makeStoreDetailView: (String) -> StoreDetailRootView
    private let makeStoreSearchView: (String) -> AnyView
    private let makeBannerWebView: (HomeBannerItem) -> AnyView
    private let makeNotificationListView: () -> AnyView
    private let makeAuthView: () -> AnyView

    init(
        storeRepository: StoreRepository,
        bannerRepository: BannerRepository,
        notificationService: AppNotificationService,
        locationService: any LocationServiceProtocol,
        reverseGeocoder: ReverseGeocoder,
        sessionStore: SessionStore,
        imageLoader: any AuthorizedImageLoading,
        makeStoreDetailView: @escaping (String) -> StoreDetailRootView,
        makeStoreSearchView: @escaping (String) -> AnyView,
        makeBannerWebView: @escaping (HomeBannerItem) -> AnyView,
        makeNotificationListView: @escaping () -> AnyView,
        makeAuthView: @escaping () -> AnyView
    ) {
        self.storeRepository = storeRepository
        self.bannerRepository = bannerRepository
        self.notificationService = notificationService
        self.locationService = locationService
        self.reverseGeocoder = reverseGeocoder
        self.sessionStore = sessionStore
        self.imageLoader = imageLoader
        self.makeStoreDetailView = makeStoreDetailView
        self.makeStoreSearchView = makeStoreSearchView
        self.makeBannerWebView = makeBannerWebView
        self.makeNotificationListView = makeNotificationListView
        self.makeAuthView = makeAuthView
    }

    func build(resetTrigger: Int = 0) -> HomeRootView {
        let router = HomeRouter()
        let interactor = HomeInteractor(
            storeRepository: storeRepository,
            bannerRepository: bannerRepository,
            notificationService: notificationService,
            locationService: locationService,
            reverseGeocoder: reverseGeocoder
        )
        let presenter = HomePresenter(
            interactor: interactor,
            router: router,
            sessionStore: sessionStore
        )
        return HomeRootView(
            presenter: presenter,
            router: router,
            imageLoader: imageLoader,
            makeStoreDetailView: makeStoreDetailView,
            makeStoreSearchView: makeStoreSearchView,
            makeBannerWebView: makeBannerWebView,
            makeNotificationListView: makeNotificationListView,
            makeAuthView: makeAuthView,
            resetTrigger: resetTrigger
        )
    }
}
