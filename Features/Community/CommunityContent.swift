import Foundation
import CoreLocation

struct CommunityFeedContent {
    let featuredBanner: CommunityFeaturedBanner?
    let posts: [CommunityPostSummary]
    let nextCursor: String?
    let referenceLocation: CommunityReferenceLocation?
}

enum CommunityFeedError: Error, Equatable {
    case authenticationRequired
    case locationRequired(message: String)
    case unavailable(message: String)
}

extension CommunityFeedError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .authenticationRequired:
            return "로그인 후 커뮤니티 피드를 확인할 수 있어요."
        case .locationRequired(let message):
            return message
        case .unavailable(let message):
            return message
        }
    }
}

enum CommunityFeedStatus: Equatable {
    case loading
    case content
    case empty
    case failure
    case locationRequired
    case authenticationRequired
}

struct CommunityEmptyState: Equatable {
    let title: String
    let message: String
    let actionTitle: String
    var requiresAuthentication = false
}

struct CommunityFeaturedBanner: Equatable {
    let eyebrow: String
    let title: String
    let badgeText: String
    let pageText: String
    let systemImage: String

    static let mock = CommunityFeaturedBanner(
        eyebrow: "새싹멤버십 전용 사용 혜택",
        title: "피자부터 커피까지\n픽업하면 0원",
        badgeText: "SeSAC ONLY",
        pageText: "1 / 12",
        systemImage: "takeoutbag.and.cup.and.straw.fill"
    )
}

struct CommunityReferenceLocation: Equatable, Sendable {
    let longitude: Double
    let latitude: Double
}

struct CommunityDistanceCalculator: Sendable {
    func distanceMeters(
        from reference: CommunityReferenceLocation?,
        toLongitude longitude: Double?,
        latitude: Double?
    ) -> Double? {
        guard let reference,
              isValidCoordinate(latitude: reference.latitude, longitude: reference.longitude),
              let longitude,
              let latitude,
              isValidCoordinate(latitude: latitude, longitude: longitude) else {
            return nil
        }

        let referenceLocation = CLLocation(latitude: reference.latitude, longitude: reference.longitude)
        let postLocation = CLLocation(latitude: latitude, longitude: longitude)
        return referenceLocation.distance(from: postLocation)
    }

    func isValidCoordinate(latitude: Double, longitude: Double) -> Bool {
        latitude.isFinite
            && longitude.isFinite
            && (-90...90).contains(latitude)
            && (-180...180).contains(longitude)
            && !(latitude == 0 && longitude == 0)
    }
}

enum CommunitySort: String, CaseIterable, Identifiable, Equatable {
    case latest
    case popular
    case nearest

    var id: String { rawValue }

    var title: String {
        switch self {
        case .latest:
            return "최신순"
        case .popular:
            return "인기순"
        case .nearest:
            return "가까운순"
        }
    }

    var systemImage: String {
        switch self {
        case .latest:
            return "clock"
        case .popular:
            return "heart"
        case .nearest:
            return "location"
        }
    }

    static let all: [CommunitySort] = allCases
}

typealias CommunitySortOption = CommunitySort

struct CommunityDistanceOption: Identifiable, Equatable {
    let id: String
    let title: String
    let meters: Double?

    static let all: [CommunityDistanceOption] = [
        CommunityDistanceOption(id: "100", title: "100M", meters: 100),
        CommunityDistanceOption(id: "300", title: "300M", meters: 300),
        CommunityDistanceOption(id: "500", title: "500M", meters: 500),
        CommunityDistanceOption(id: "1000", title: "1KM", meters: 1_000),
        CommunityDistanceOption(id: "2000", title: "2KM", meters: 2_000),
        CommunityDistanceOption(id: "3000", title: "3KM", meters: 3_000)
    ]

    static let defaultOption = all[1]
}

enum CommunityFilter: String, CaseIterable, Identifiable, Equatable, Hashable {
    case nearbyOnly = "nearby"
    case videoOnly = "video"
    case storeTag = "store"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .nearbyOnly:
            return "근처만"
        case .videoOnly:
            return "영상포함"
        case .storeTag:
            return "가게태그"
        }
    }

    var systemImage: String? {
        switch self {
        case .nearbyOnly:
            return "location"
        case .videoOnly:
            return "play.rectangle"
        case .storeTag:
            return "storefront"
        }
    }

    static let defaults: [CommunityFilter] = allCases
}

typealias CommunityFilterChip = CommunityFilter

struct CommunityPostChangeNotification: Sendable {
    let postID: String
    let isLiked: Bool?
    let likeCount: Int?
    let commentCount: Int?
}

extension Notification.Name {
    static let pikkoCommunityPostDidChange = Notification.Name("pikko.community.postDidChange")
}

enum CommunityPostChangeNotificationUserInfoKey {
    static let event = "event"
}
