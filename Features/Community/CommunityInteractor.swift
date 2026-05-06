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
            #if DEBUG
            Logger.shared.debug(
                "[CommunityFilter] selected distance=\(selectedDistance.title) direction=\(selectedSort.direction.rawValue) orderBy=\(selectedSort.requestOrderBy.rawValue)"
            )
            #endif
            if let query = normalizedQuery(query) {
                let referenceLocation = await resolveReferenceLocation()
            #if DEBUG
            Logger.shared.debug(
                "[CommunityList] request category=\(selectedSort.category.id) direction=\(selectedSort.direction.rawValue) distance=\(selectedDistance.title) hasLocation=\(referenceLocation != nil) cursor=nil"
            )
            logLocation(referenceLocation: referenceLocation)
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
                "[CommunityList] request category=\(selectedSort.category.id) direction=\(selectedSort.direction.rawValue) distance=\(selectedDistance.title) hasLocation=\(locationContext.referenceLocation != nil) cursor=nil"
            )
            logLocation(referenceLocation: locationContext.referenceLocation)
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
        } catch is CancellationError {
            throw CancellationError()
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
                "[CommunityFilter] selected distance=\(selectedDistance.title) direction=\(selectedSort.direction.rawValue) orderBy=\(selectedSort.requestOrderBy.rawValue)"
            )
            #endif
            #if DEBUG
            Logger.shared.debug(
                "[CommunityList] request category=\(selectedSort.category.id) direction=\(selectedSort.direction.rawValue) distance=\(selectedDistance.title) hasLocation=\(locationContext.referenceLocation != nil) cursor=\(nextCursor)"
            )
            logLocation(referenceLocation: locationContext.referenceLocation)
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
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw map(error)
        }
    }

    func loadPost(postID: String) async throws -> CommunityPostSummary {
        do {
            return try await communityRepository.fetchPostDetail(postID: postID).summary
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw map(error)
        }
    }

    func updateLikeStatus(postID: String, isLiked: Bool) async throws -> Bool {
        do {
            return try await communityRepository.updateLikeStatus(postID: postID, isLiked: isLiked)
        } catch is CancellationError {
            throw CancellationError()
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
        selectedSort.requestOrderBy
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
            throw CommunityFeedError.locationRequired(message: "현재 위치를 확인한 뒤 다시 시도해 주세요.")
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
        } catch is CancellationError {
            throw CancellationError()
        } catch LocationServiceError.authorizationNotDetermined {
            locationService.requestWhenInUseAuthorization()
            #if DEBUG
            Logger.shared.info("[CommunityLocation] location pending, waitingForPermission")
            #endif
            throw CommunityFeedError.locationRequired(message: "위치 권한을 허용한 뒤 다시 시도해 주세요.")
        } catch LocationServiceError.unauthorized, LocationServiceError.servicesDisabled {
            #if DEBUG
            Logger.shared.info("[CommunityLocation] location unavailable permission=\(locationService.authorizationStatus.debugName)")
            #endif
            throw CommunityFeedError.locationRequired(message: "거리순 게시글을 보려면 위치 권한이 필요해요.")
        } catch LocationServiceError.noLocationAvailable {
            #if DEBUG
            Logger.shared.info("[CommunityLocation] location pending, noLocationAvailable")
            #endif
            throw CommunityFeedError.locationRequired(message: "현재 위치를 확인한 뒤 다시 시도해 주세요.")
        } catch {
            #if DEBUG
            Logger.shared.info("[CommunityLocation] location pending, error=\(error.localizedDescription)")
            #endif
            throw CommunityFeedError.locationRequired(message: "현재 위치를 확인하지 못했어요. 잠시 후 다시 시도해 주세요.")
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
            return .unavailable(message: "데이터를 불러오지 못했어요.")
        case .transport:
            Logger.shared.warning("[CommunityList] network failed error=transport")
            return .networkUnavailable(message: "네트워크 연결을 확인한 뒤 다시 시도해 주세요.")
        case .unauthorized, .authenticationFailed, .accessTokenExpired, .refreshTokenExpired, .configuration:
            return .unavailable(message: networkError.localizedDescription)
        }
    }

    private func logLocation(referenceLocation: CommunityReferenceLocation?) {
        #if DEBUG
        Logger.shared.debug(
            "[CommunityLocation] latExists=\(referenceLocation?.latitude != nil) lonExists=\(referenceLocation?.longitude != nil) permission=\(locationService.authorizationStatus.debugName)"
        )
        #endif
    }
}

private struct CommunityLocationContext {
    let referenceLocation: CommunityReferenceLocation?
    let longitude: Double?
    let latitude: Double?
}

private extension CLAuthorizationStatus {
    var debugName: String {
        switch self {
        case .notDetermined:
            return "notDetermined"
        case .restricted:
            return "restricted"
        case .denied:
            return "denied"
        case .authorizedAlways:
            return "authorizedAlways"
        case .authorizedWhenInUse:
            return "authorizedWhenInUse"
        @unknown default:
            return "unknown"
        }
    }
}
