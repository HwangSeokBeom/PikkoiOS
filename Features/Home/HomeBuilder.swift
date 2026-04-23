import Foundation

@MainActor
struct HomeBuilder {
    private let storeRepository: StoreRepository
    private let bannerRepository: BannerRepository
    private let locationService: any LocationServiceProtocol
    private let reverseGeocoder: ReverseGeocoder
    private let imageLoader: any AuthorizedImageLoading

    init(
        storeRepository: StoreRepository,
        bannerRepository: BannerRepository,
        locationService: any LocationServiceProtocol,
        reverseGeocoder: ReverseGeocoder,
        imageLoader: any AuthorizedImageLoading
    ) {
        self.storeRepository = storeRepository
        self.bannerRepository = bannerRepository
        self.locationService = locationService
        self.reverseGeocoder = reverseGeocoder
        self.imageLoader = imageLoader
    }

    func build() -> HomeRootView {
        let router = HomeRouter()
        let interactor = HomeInteractor(
            storeRepository: storeRepository,
            bannerRepository: bannerRepository,
            locationService: locationService,
            reverseGeocoder: reverseGeocoder
        )
        let presenter = HomePresenter(interactor: interactor, router: router)
        return HomeRootView(
            presenter: presenter,
            imageLoader: imageLoader
        )
    }
}
