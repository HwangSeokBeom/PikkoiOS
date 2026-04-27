import CoreLocation
import Foundation

@MainActor
protocol CommunityInteracting {
    func loadFeed(
        query: String?,
        selectedDistance: CommunityDistanceOption,
        selectedSort: CommunitySort
    ) async throws -> CommunityFeedContent

    func loadMorePosts(
        selectedDistance: CommunityDistanceOption,
        selectedSort: CommunitySort,
        nextCursor: String
    ) async throws -> CommunityFeedContent

    func loadPost(postID: String) async throws -> CommunityPostSummary
    func updateLikeStatus(postID: String, isLiked: Bool) async throws -> Bool
}

@MainActor
struct CommunityInteractor: CommunityInteracting {
    private let communityRepository: CommunityRepository
    private let locationService: any LocationServiceProtocol
    private let distanceCalculator = CommunityDistanceCalculator()

    init(
        communityRepository: CommunityRepository,
        locationService: any LocationServiceProtocol
    ) {
        self.communityRepository = communityRepository
        self.locationService = locationService
    }

    func loadFeed(
        query: String?,
        selectedDistance: CommunityDistanceOption,
        selectedSort: CommunitySort
    ) async throws -> CommunityFeedContent {
        do {
            if let query = normalizedQuery(query) {
                let referenceLocation = await resolveReferenceLocation()
                #if DEBUG
                Logger.shared.debug(
                    "[CommunityList] request query cursor=nil sort=\(selectedSort.id) distance=\(selectedDistance.title) hasLocation=\(referenceLocation != nil)"
                )
                Logger.shared.debug("[CommunityDistance] selected latExists=\(referenceLocation?.latitude != nil) lonExists=\(referenceLocation?.longitude != nil)")
                #endif
                let posts = try await communityRepository.searchPosts(title: query)
                #if DEBUG
                Logger.shared.debug("[CommunityList] response count=\(posts.count) nextCursor=nil")
                #endif
                return CommunityFeedContent(
                    featuredBanner: nil,
                    posts: posts,
                    nextCursor: nil,
                    referenceLocation: referenceLocation
                )
            }

            let locationContext = try await resolveLocationContext(requestIfNeeded: true)
            #if DEBUG
            Logger.shared.debug(
                "[CommunityList] request query cursor=nil sort=\(selectedSort.id) distance=\(selectedDistance.title) hasLocation=\(locationContext.referenceLocation != nil)"
            )
            Logger.shared.debug("[CommunityDistance] selected latExists=\(locationContext.referenceLocation?.latitude != nil) lonExists=\(locationContext.referenceLocation?.longitude != nil)")
            #endif
            let page = try await communityRepository.fetchGeolocationPosts(
                category: nil,
                longitude: locationContext.longitude,
                latitude: locationContext.latitude,
                maxDistance: locationContext.referenceLocation != nil ? selectedDistance.meters : nil,
                nextCursor: nil,
                limit: 5,
                orderBy: serverSortOrder(for: selectedSort)
            )
            #if DEBUG
            Logger.shared.debug("[CommunityList] response count=\(page.items.count) nextCursor=\(page.nextCursor ?? "nil")")
            #endif

            return CommunityFeedContent(
                featuredBanner: nil,
                posts: page.items,
                nextCursor: page.nextCursor,
                referenceLocation: locationContext.referenceLocation
            )
        } catch {
            let mappedError = map(error)
            throw mappedError
        }
    }

    func loadMorePosts(
        selectedDistance: CommunityDistanceOption,
        selectedSort: CommunitySort,
        nextCursor: String
    ) async throws -> CommunityFeedContent {
        do {
            let locationContext = try await resolveLocationContext(requestIfNeeded: false)
            #if DEBUG
            Logger.shared.debug(
                "[CommunityList] request query cursor=\(nextCursor) sort=\(selectedSort.id) distance=\(selectedDistance.title) hasLocation=\(locationContext.referenceLocation != nil)"
            )
            Logger.shared.debug("[CommunityDistance] selected latExists=\(locationContext.referenceLocation?.latitude != nil) lonExists=\(locationContext.referenceLocation?.longitude != nil)")
            #endif
            let page = try await communityRepository.fetchGeolocationPosts(
                category: nil,
                longitude: locationContext.longitude,
                latitude: locationContext.latitude,
                maxDistance: locationContext.referenceLocation != nil ? selectedDistance.meters : nil,
                nextCursor: nextCursor,
                limit: 5,
                orderBy: serverSortOrder(for: selectedSort)
            )
            #if DEBUG
            Logger.shared.debug("[CommunityList] response count=\(page.items.count) nextCursor=\(page.nextCursor ?? "nil")")
            #endif

            return CommunityFeedContent(
                featuredBanner: nil,
                posts: page.items,
                nextCursor: page.nextCursor,
                referenceLocation: locationContext.referenceLocation
            )
        } catch {
            throw map(error)
        }
    }

    func loadPost(postID: String) async throws -> CommunityPostSummary {
        do {
            return try await communityRepository.fetchPostDetail(postID: postID).summary
        } catch {
            throw map(error)
        }
    }

    func updateLikeStatus(postID: String, isLiked: Bool) async throws -> Bool {
        do {
            return try await communityRepository.updateLikeStatus(postID: postID, isLiked: isLiked)
        } catch {
            throw map(error)
        }
    }

    private func normalizedQuery(_ query: String?) -> String? {
        guard let trimmed = query?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return nil
        }

        return trimmed
    }

    private func serverSortOrder(for selectedSort: CommunitySort) -> CommunityPostSortOrder {
        switch selectedSort {
        case .popular:
            return .likes
        case .latest, .nearest:
            return .createdAt
        }
    }

    private func resolveReferenceLocation() async -> CommunityReferenceLocation? {
        if let selectedLocation = SelectedLocationStore.shared.selectedLocation,
           distanceCalculator.isValidCoordinate(
               latitude: selectedLocation.latitude,
               longitude: selectedLocation.longitude
           ) {
            return .init(
                longitude: selectedLocation.longitude,
                latitude: selectedLocation.latitude
            )
        }

        guard let currentLocation = locationService.currentLocation,
              distanceCalculator.isValidCoordinate(
                  latitude: currentLocation.coordinate.latitude,
                  longitude: currentLocation.coordinate.longitude
              ) else {
            return nil
        }

        return .init(
            longitude: currentLocation.coordinate.longitude,
            latitude: currentLocation.coordinate.latitude
        )
    }

    private func resolveLocationContext(requestIfNeeded: Bool) async throws -> CommunityLocationContext {
        if let selectedLocation = SelectedLocationStore.shared.selectedLocation,
           distanceCalculator.isValidCoordinate(
               latitude: selectedLocation.latitude,
               longitude: selectedLocation.longitude
           ) {
            return CommunityLocationContext(
                referenceLocation: .init(
                    longitude: selectedLocation.longitude,
                    latitude: selectedLocation.latitude
                ),
                longitude: selectedLocation.longitude,
                latitude: selectedLocation.latitude
            )
        }

        if let currentLocation = locationService.currentLocation,
           distanceCalculator.isValidCoordinate(
               latitude: currentLocation.coordinate.latitude,
               longitude: currentLocation.coordinate.longitude
           ) {
            return makeLocationContext(from: currentLocation)
        }

        guard requestIfNeeded else {
            throw CommunityFeedError.locationRequired(message: "위치를 선택하거나 현재 위치 권한을 허용해 주세요.")
        }

        do {
            let location = try await locationService.requestCurrentLocation()
            guard distanceCalculator.isValidCoordinate(
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude
            ) else {
                throw CommunityFeedError.locationRequired(message: "현재 위치 좌표를 확인하지 못했어요. 위치를 선택한 뒤 다시 시도해 주세요.")
            }
            return makeLocationContext(from: location)
        } catch LocationServiceError.authorizationNotDetermined {
            locationService.requestWhenInUseAuthorization()
            throw CommunityFeedError.locationRequired(message: "커뮤니티 피드를 보려면 위치 권한을 허용해 주세요.")
        } catch LocationServiceError.unauthorized, LocationServiceError.servicesDisabled {
            throw CommunityFeedError.locationRequired(message: "위치를 선택하거나 현재 위치 권한을 허용해 주세요.")
        } catch LocationServiceError.noLocationAvailable {
            throw CommunityFeedError.locationRequired(message: "현재 위치를 확인하지 못했어요. 위치를 선택한 뒤 다시 시도해 주세요.")
        } catch {
            Logger.shared.debug("Community location resolution failed; using the app default location.")
            throw CommunityFeedError.locationRequired(message: "현재 위치를 확인하지 못했어요. 위치를 선택한 뒤 다시 시도해 주세요.")
        }
    }

    private func makeLocationContext(from location: CLLocation) -> CommunityLocationContext {
        CommunityLocationContext(
            referenceLocation: .init(
                longitude: location.coordinate.longitude,
                latitude: location.coordinate.latitude
            ),
            longitude: location.coordinate.longitude,
            latitude: location.coordinate.latitude
        )
    }

    private func map(_ error: Error) -> CommunityFeedError {
        if let communityError = error as? CommunityFeedError {
            return communityError
        }

        guard let networkError = error as? NetworkError else {
            return .unavailable(message: error.localizedDescription)
        }

        if networkError.isAuthenticationFailure {
            return .authenticationRequired
        }

        if networkError.isConfigurationFailure {
            return .unavailable(
                message: networkError.appConfigurationError?.userMessage ?? "앱 설정을 확인해 주세요."
            )
        }

        switch networkError {
        case .invalidRequest, .abnormalRequest:
            return .unavailable(message: "커뮤니티 요청 형식이 올바르지 않아요.")
        case .forbidden:
            return .unavailable(message: "커뮤니티 접근 권한이 없어요.")
        case .rateLimited:
            return .unavailable(message: "요청이 너무 많아요. 잠시 후 다시 시도해 주세요.")
        case .notFound(let message),
             .conflict(let message),
             .businessAuthorization(let message),
             .server(let message):
            return .unavailable(message: message)
        case .decoding:
            return .unavailable(message: "커뮤니티 응답을 해석하지 못했어요.")
        case .transport:
            return .unavailable(message: "네트워크 연결을 확인한 뒤 다시 시도해 주세요.")
        case .unauthorized, .accessTokenExpired, .refreshTokenExpired, .configuration:
            return .unavailable(message: networkError.localizedDescription)
        }
    }
}

private struct CommunityLocationContext {
    let referenceLocation: CommunityReferenceLocation?
    let longitude: Double?
    let latitude: Double?
}
