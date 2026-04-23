import CoreLocation
import Foundation

@MainActor
protocol HomeInteracting {
    func loadHome(category: String?) async throws -> HomeContent
    func loadMoreNearbyStores(category: String?, nextCursor: String) async throws -> CursorPage<StoreSummary>
    func updateLikeStatus(storeID: String, isLiked: Bool) async throws -> Bool
}

@MainActor
struct HomeInteractor: HomeInteracting {
    private let storeRepository: StoreRepository
    private let bannerRepository: BannerRepository
    private let locationService: any LocationServiceProtocol
    private let reverseGeocoder: ReverseGeocoder

    init(
        storeRepository: StoreRepository,
        bannerRepository: BannerRepository,
        locationService: any LocationServiceProtocol,
        reverseGeocoder: ReverseGeocoder
    ) {
        self.storeRepository = storeRepository
        self.bannerRepository = bannerRepository
        self.locationService = locationService
        self.reverseGeocoder = reverseGeocoder
    }

    func loadHome(category: String?) async throws -> HomeContent {
        let locationContext = await resolveLocationContext(requestIfNeeded: true)

        async let popularKeywords = storeRepository.fetchPopularSearchTerms()
        async let banners = bannerRepository.fetchMainBanners()
        async let popularStores = storeRepository.fetchPopularStores(category: category)
        async let nearbyStores = storeRepository.fetchNearbyStores(
            category: category,
            longitude: locationContext.longitude,
            latitude: locationContext.latitude,
            maxDistance: 3000,
            nextCursor: nil,
            limit: 5,
            orderBy: .distance
        )

        return try await HomeContent(
            locationLabel: locationContext.label,
            popularKeywords: popularKeywords,
            banners: banners,
            popularStores: popularStores,
            nearbyStoresPage: nearbyStores
        )
    }

    func loadMoreNearbyStores(category: String?, nextCursor: String) async throws -> CursorPage<StoreSummary> {
        let locationContext = await resolveLocationContext(requestIfNeeded: false)
        return try await storeRepository.fetchNearbyStores(
            category: category,
            longitude: locationContext.longitude,
            latitude: locationContext.latitude,
            maxDistance: 3000,
            nextCursor: nextCursor,
            limit: 5,
            orderBy: .distance
        )
    }

    func updateLikeStatus(storeID: String, isLiked: Bool) async throws -> Bool {
        try await storeRepository.updateLikeStatus(storeID: storeID, isLiked: isLiked)
    }

    private func resolveLocationContext(requestIfNeeded: Bool) async -> HomeLocationContext {
        if let currentLocation = locationService.currentLocation {
            return await makeLocationContext(from: currentLocation)
        }

        guard requestIfNeeded else {
            return HomeLocationContext(label: "현재 위치 주변", longitude: nil, latitude: nil)
        }

        do {
            let location = try await locationService.requestCurrentLocation()
            return await makeLocationContext(from: location)
        } catch LocationServiceError.authorizationNotDetermined {
            locationService.requestWhenInUseAuthorization()
        } catch {
            Logger.shared.warning("Home location resolution failed: \(error.localizedDescription)")
        }

        return HomeLocationContext(label: "현재 위치 주변", longitude: nil, latitude: nil)
    }

    private func makeLocationContext(from location: CLLocation) async -> HomeLocationContext {
        let label: String

        do {
            let resolvedLabel = try await reverseGeocoder.resolveDisplayName(for: location)
            label = resolvedLabel.isEmpty ? "현재 위치 주변" : resolvedLabel
        } catch {
            Logger.shared.warning("Reverse geocoding failed: \(error.localizedDescription)")
            label = "현재 위치 주변"
        }

        return HomeLocationContext(
            label: label,
            longitude: location.coordinate.longitude,
            latitude: location.coordinate.latitude
        )
    }
}

private struct HomeLocationContext {
    let label: String
    let longitude: Double?
    let latitude: Double?
}
