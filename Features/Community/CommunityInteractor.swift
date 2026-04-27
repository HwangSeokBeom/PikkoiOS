import CoreLocation
import Foundation

@MainActor
protocol CommunityInteracting {
    func loadFeed(
        query: String?,
        selectedDistance: CommunityDistanceOption,
        selectedSort: CommunitySortOption
    ) async throws -> CommunityFeedContent

    func loadMorePosts(
        selectedDistance: CommunityDistanceOption,
        selectedSort: CommunitySortOption,
        nextCursor: String
    ) async throws -> CommunityFeedContent

    func updateLikeStatus(postID: String, isLiked: Bool) async throws -> Bool
}

@MainActor
struct CommunityInteractor: CommunityInteracting {
    private let communityRepository: CommunityRepository
    private let locationService: any LocationServiceProtocol

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
        selectedSort: CommunitySortOption
    ) async throws -> CommunityFeedContent {
        do {
            let locationContext = await resolveLocationContext(requestIfNeeded: true)

            if let query = normalizedQuery(query) {
                let posts = try await communityRepository.searchPosts(title: query)
                return CommunityFeedContent(
                    featuredBanner: .mock,
                    posts: posts,
                    nextCursor: nil,
                    referenceLocation: locationContext.referenceLocation
                )
            }

            let page = try await communityRepository.fetchGeolocationPosts(
                category: nil,
                longitude: locationContext.longitude,
                latitude: locationContext.latitude,
                maxDistance: locationContext.referenceLocation != nil ? selectedDistance.meters : nil,
                nextCursor: nil,
                limit: 5,
                orderBy: serverSortOrder(for: selectedSort)
            )

            return CommunityFeedContent(
                featuredBanner: .mock,
                posts: page.items,
                nextCursor: page.nextCursor,
                referenceLocation: locationContext.referenceLocation
            )
        } catch {
            let mappedError = map(error)
            if case .authenticationRequired = mappedError {
                throw mappedError
            }
            Logger.shared.warning("Community feed falling back to local content: \(mappedError.localizedDescription)")
            return makeFallbackContent(query: query)
        }
    }

    func loadMorePosts(
        selectedDistance: CommunityDistanceOption,
        selectedSort: CommunitySortOption,
        nextCursor: String
    ) async throws -> CommunityFeedContent {
        do {
            let locationContext = await resolveLocationContext(requestIfNeeded: false)
            let page = try await communityRepository.fetchGeolocationPosts(
                category: nil,
                longitude: locationContext.longitude,
                latitude: locationContext.latitude,
                maxDistance: locationContext.referenceLocation != nil ? selectedDistance.meters : nil,
                nextCursor: nextCursor,
                limit: 5,
                orderBy: serverSortOrder(for: selectedSort)
            )

            return CommunityFeedContent(
                featuredBanner: .mock,
                posts: page.items,
                nextCursor: page.nextCursor,
                referenceLocation: locationContext.referenceLocation
            )
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

    private func serverSortOrder(for selectedSort: CommunitySortOption) -> CommunityPostSortOrder {
        switch selectedSort.id {
        case CommunitySortOption.popular.id:
            return .likes
        default:
            return .createdAt
        }
    }

    private func makeFallbackContent(query: String?) -> CommunityFeedContent {
        let normalizedQuery = normalizedQuery(query)?.lowercased()
        let posts = [
            CommunityPostSummary(
                id: "local-community-fallback-1",
                category: "디저트",
                title: "근처 픽업 후기를 준비 중이에요",
                content: "네트워크 응답을 받지 못해 임시 게시글을 보여드려요. 연결이 복구되면 실제 커뮤니티 글로 자동 갱신됩니다.",
                creator: CommunityPostAuthor(id: "local-fallback-user", nick: "픽코", profileImagePath: nil),
                mediaPaths: ["community-fallback-dessert"],
                store: nil,
                isLiked: false,
                likeCount: 0,
                longitude: nil,
                latitude: nil,
                createdAt: Date(),
                updatedAt: nil
            )
        ]
        let filteredPosts = posts.filter {
            guard let normalizedQuery else { return true }
            return $0.title.lowercased().contains(normalizedQuery)
                || $0.content.lowercased().contains(normalizedQuery)
        }
        return CommunityFeedContent(
            featuredBanner: .mock,
            posts: filteredPosts,
            nextCursor: nil,
            referenceLocation: nil
        )
    }

    private func resolveLocationContext(requestIfNeeded: Bool) async -> CommunityLocationContext {
        if let currentLocation = locationService.currentLocation {
            return makeLocationContext(from: currentLocation)
        }

        guard requestIfNeeded else {
            return CommunityLocationContext(referenceLocation: nil, longitude: nil, latitude: nil)
        }

        do {
            let location = try await locationService.requestCurrentLocation()
            return makeLocationContext(from: location)
        } catch LocationServiceError.authorizationNotDetermined {
            locationService.requestWhenInUseAuthorization()
        } catch {
            Logger.shared.warning("Community location resolution failed: \(error.localizedDescription)")
        }

        return CommunityLocationContext(referenceLocation: nil, longitude: nil, latitude: nil)
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
