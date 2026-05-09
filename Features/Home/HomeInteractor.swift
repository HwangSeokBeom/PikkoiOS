import CoreLocation
import Foundation

@MainActor
enum HomeLocationRequestResult: Equatable {
    case available
    case authorizationRequested
    case permissionDenied
    case unavailable(String)
}

@MainActor
protocol HomeInteracting {
    func loadHome(category: String?) async throws -> HomeContent
    func loadHome(category: String?, orderBy: StoreSortOrder) async throws -> HomeContent
    func loadMoreNearbyStores(category: String?, nextCursor: String, orderBy: StoreSortOrder) async throws -> CursorPage<StoreSummary>
    func updateLikeStatus(storeID: String, isLiked: Bool) async throws -> Bool
    func notificationUnreadCount() -> Int
    func requestCurrentLocationForHome() async -> HomeLocationRequestResult
    func saveSelectedLocation(_ location: PikkoSelectedLocation)
}

@MainActor
struct HomeInteractor: HomeInteracting {
    private let storeRepository: StoreRepository
    private let bannerRepository: BannerRepository
    private let notificationService: AppNotificationService
    private let locationService: any LocationServiceProtocol
    private let reverseGeocoder: ReverseGeocoder

    init(
        storeRepository: StoreRepository,
        bannerRepository: BannerRepository,
        notificationService: AppNotificationService,
        locationService: any LocationServiceProtocol,
        reverseGeocoder: ReverseGeocoder
    ) {
        self.storeRepository = storeRepository
        self.bannerRepository = bannerRepository
        self.notificationService = notificationService
        self.locationService = locationService
        self.reverseGeocoder = reverseGeocoder
    }

    func loadHome(category: String?) async throws -> HomeContent {
        try await loadHome(category: category, orderBy: .distance)
    }

    func loadHome(category: String?, orderBy: StoreSortOrder) async throws -> HomeContent {
        do {
            let locationContext = await resolveLocationContext(requestIfNeeded: true)

            async let popularKeywordsResult = loadSection("popularKeywords") {
                try await storeRepository.fetchPopularSearchTerms()
            }
            async let bannersResult = loadSection("banners") {
                try await bannerRepository.fetchMainBanners()
            }
            async let popularStoresResult = loadSection("popularStores") {
                try await storeRepository.fetchPopularStores(category: category)
            }
            async let nearbyStoresResult = loadSection("nearbyStores") {
                try await storeRepository.fetchNearbyStores(
                    category: category,
                    longitude: locationContext.longitude,
                    latitude: locationContext.latitude,
                    maxDistance: 3000,
                    nextCursor: nil,
                    limit: 10,
                    orderBy: orderBy
                )
            }

            let popularKeywords = await popularKeywordsResult
            let banners = await bannersResult
            let popularStores = await popularStoresResult
            let nearbyStores = await nearbyStoresResult

            let content = HomeContent(
                locationLabel: locationContext.label,
                popularKeywords: popularKeywords.value ?? [],
                banners: banners.value ?? [],
                popularStores: popularStores.value ?? [],
                nearbyStoresPage: nearbyStores.value ?? CursorPage(items: [], nextCursor: nil),
                sectionMessages: HomeSectionMessages(
                    popularKeywords: sectionMessage(for: popularKeywords.error),
                    banners: sectionMessage(for: banners.error),
                    popularStores: sectionMessage(for: popularStores.error),
                    nearbyStores: sectionMessage(for: nearbyStores.error)
                )
            )

            if popularKeywords.value != nil
                || banners.value != nil
                || popularStores.value != nil
                || nearbyStores.value != nil {
                return content
            }

            throw firstFailure(
                popularKeywords.error,
                banners.error,
                popularStores.error,
                nearbyStores.error
            ) ?? HomeFeedError.unavailable(message: "네트워크 연결을 확인한 뒤 다시 시도해 주세요.")
        } catch {
            throw map(error)
        }
    }

    func loadMoreNearbyStores(category: String?, nextCursor: String) async throws -> CursorPage<StoreSummary> {
        try await loadMoreNearbyStores(category: category, nextCursor: nextCursor, orderBy: .distance)
    }

    func loadMoreNearbyStores(category: String?, nextCursor: String, orderBy: StoreSortOrder) async throws -> CursorPage<StoreSummary> {
        do {
            let locationContext = await resolveLocationContext(requestIfNeeded: false)
            return try await storeRepository.fetchNearbyStores(
                category: category,
                longitude: locationContext.longitude,
                latitude: locationContext.latitude,
                maxDistance: 3000,
                nextCursor: nextCursor,
                limit: 10,
                orderBy: orderBy
            )
        } catch {
            throw map(error)
        }
    }

    func updateLikeStatus(storeID: String, isLiked: Bool) async throws -> Bool {
        do {
            return try await storeRepository.updateLikeStatus(storeID: storeID, isLiked: isLiked)
        } catch {
            throw map(error)
        }
    }

    func notificationUnreadCount() -> Int {
        notificationService.unreadCount()
    }

    func requestCurrentLocationForHome() async -> HomeLocationRequestResult {
        switch locationService.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            return await requestCurrentLocation()
        case .notDetermined:
            locationService.requestWhenInUseAuthorization()
            let decision = await waitForLocationAuthorizationDecision()
            switch decision {
            case .authorizedAlways, .authorizedWhenInUse:
                return await requestCurrentLocation()
            case .denied, .restricted:
                return .permissionDenied
            case .notDetermined:
                return .authorizationRequested
            @unknown default:
                return .permissionDenied
            }
        case .denied, .restricted:
            return .permissionDenied
        @unknown default:
            return .permissionDenied
        }
    }

    func saveSelectedLocation(_ location: PikkoSelectedLocation) {
        SelectedLocationStore.shared.save(location)
    }

    private func resolveLocationContext(requestIfNeeded: Bool) async -> HomeLocationContext {
        if let selectedLocation = SelectedLocationStore.shared.selectedLocation {
            return HomeLocationContext(
                label: selectedLocation.displayName,
                longitude: selectedLocation.longitude,
                latitude: selectedLocation.latitude
            )
        }

        if let currentLocation = locationService.currentLocation {
            return await makeLocationContext(from: currentLocation)
        }

        guard requestIfNeeded else {
            return defaultLocationContext()
        }

        do {
            let location = try await locationService.requestCurrentLocation()
            return await makeLocationContext(from: location)
        } catch LocationServiceError.authorizationNotDetermined {
            locationService.requestWhenInUseAuthorization()
        } catch {
            Logger.shared.info("Home feed requested without a resolved location.")
        }

        return defaultLocationContext()
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

    private func requestCurrentLocation() async -> HomeLocationRequestResult {
        do {
            let location = try await locationService.requestCurrentLocation()
            let context = await makeLocationContext(from: location)
            SelectedLocationStore.shared.save(
                PikkoSelectedLocation(
                    title: context.label,
                    subtitle: nil,
                    latitude: location.coordinate.latitude,
                    longitude: location.coordinate.longitude,
                    source: "currentLocation"
                )
            )
            return .available
        } catch LocationServiceError.authorizationNotDetermined {
            locationService.requestWhenInUseAuthorization()
            return .authorizationRequested
        } catch LocationServiceError.unauthorized {
            return .permissionDenied
        } catch LocationServiceError.servicesDisabled {
            return .unavailable("기기의 위치 서비스가 꺼져 있어요. 설정에서 위치 서비스를 켜 주세요.")
        } catch LocationServiceError.noLocationAvailable {
            return .unavailable("현재 위치를 확인하지 못했어요. 잠시 후 다시 시도해 주세요.")
        } catch {
            return .unavailable("현재 위치를 확인하지 못했어요. 잠시 후 다시 시도해 주세요.")
        }
    }

    private func waitForLocationAuthorizationDecision() async -> CLAuthorizationStatus {
        for _ in 0..<150 {
            let status = locationService.authorizationStatus
            guard status == .notDetermined else {
                return status
            }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }

        return locationService.authorizationStatus
    }

    private func defaultLocationContext() -> HomeLocationContext {
        HomeLocationContext(
            label: LocationDefaults.defaultSelectedLocation.displayName,
            longitude: LocationDefaults.defaultSelectedLocation.longitude,
            latitude: LocationDefaults.defaultSelectedLocation.latitude
        )
    }

    private func map(_ error: Error) -> HomeFeedError {
        if let homeError = error as? HomeFeedError {
            return homeError
        }

        guard let networkError = error as? NetworkError else {
            return .unavailable(message: error.localizedDescription)
        }

        if networkError.isAuthenticationFailure {
            return .authenticationRequired
        }

        if networkError.isConfigurationFailure {
            return .configurationRequired(
                message: networkError.appConfigurationError?.userMessage ?? "앱 설정을 확인해 주세요."
            )
        }

        switch networkError {
        case .invalidRequest, .abnormalRequest:
            return .unavailable(message: "홈 요청 형식이 올바르지 않아요.")
        case .forbidden:
            return .unavailable(message: "홈 정보 접근 권한이 없어요.")
        case .rateLimited:
            return .unavailable(message: "요청이 너무 많아요. 잠시 후 다시 시도해 주세요.")
        case .notFound(let message),
             .conflict(let message),
             .businessAuthorization(let message):
            return .unavailable(message: message)
        case .server:
            return .unavailable(message: "서버 응답이 원활하지 않습니다. 잠시 후 다시 시도해 주세요.")
        case .decoding:
            return .unavailable(message: "홈 정보를 잠시 불러오지 못했어요. 잠시 후 다시 시도해 주세요.")
        case .transport:
            return .unavailable(message: "네트워크 연결을 확인한 뒤 다시 시도해 주세요.")
        case .unauthorized, .authenticationFailed, .accessTokenExpired, .refreshTokenExpired:
            return .unavailable(message: networkError.localizedDescription)
        case .configuration(let error):
            return .configurationRequired(message: error.userMessage)
        }
    }

    private func loadSection<Value: Sendable>(
        _ sectionName: String,
        operation: @escaping @MainActor () async throws -> Value
    ) async -> HomeSectionLoadResult<Value> {
        do {
            return HomeSectionLoadResult(value: try await operation(), error: nil)
        } catch {
            let mappedError = map(error)
            Logger.shared.info("Home \(sectionName) section unavailable: \(mappedError.localizedDescription)")
            return HomeSectionLoadResult(value: nil, error: mappedError)
        }
    }

    private func sectionMessage(for error: HomeFeedError?) -> String? {
        error?.localizedDescription
    }

    private func firstFailure(_ errors: HomeFeedError?...) -> HomeFeedError? {
        errors.compactMap { $0 }.first
    }
}

private struct HomeLocationContext: Sendable {
    let label: String
    let longitude: Double?
    let latitude: Double?
}

private struct HomeSectionLoadResult<Value: Sendable>: Sendable {
    let value: Value?
    let error: HomeFeedError?
}
