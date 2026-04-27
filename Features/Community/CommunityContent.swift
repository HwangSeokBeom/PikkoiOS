import Foundation

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

struct CommunitySortOption: Identifiable, Equatable {
    let id: String
    let title: String

    static let latest = CommunitySortOption(id: "latest", title: "최신순")
    static let popular = CommunitySortOption(id: "popular", title: "인기순")
    static let nearest = CommunitySortOption(id: "nearest", title: "가까운순")

    static let all: [CommunitySortOption] = [.latest, .popular, .nearest]
}

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

struct CommunityFilterChip: Identifiable, Equatable {
    let id: String
    let title: String
    let systemImage: String?

    static let defaults: [CommunityFilterChip] = [
        CommunityFilterChip(id: "nearby", title: "근처만", systemImage: "location"),
        CommunityFilterChip(id: "video", title: "영상포함", systemImage: "play.rectangle"),
        CommunityFilterChip(id: "store", title: "가게태그", systemImage: "storefront")
    ]
}
