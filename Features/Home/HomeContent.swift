import Foundation

struct HomeContent: Sendable {
    let locationLabel: String
    let popularKeywords: [String]
    let banners: [Banner]
    let popularStores: [StoreSummary]
    let nearbyStoresPage: CursorPage<StoreSummary>
    let sectionMessages: HomeSectionMessages

    init(
        locationLabel: String,
        popularKeywords: [String],
        banners: [Banner],
        popularStores: [StoreSummary],
        nearbyStoresPage: CursorPage<StoreSummary>,
        sectionMessages: HomeSectionMessages = .none
    ) {
        self.locationLabel = locationLabel
        self.popularKeywords = popularKeywords
        self.banners = banners
        self.popularStores = popularStores
        self.nearbyStoresPage = nearbyStoresPage
        self.sectionMessages = sectionMessages
    }

    var hasRenderableSections: Bool {
        !banners.isEmpty || !popularStores.isEmpty || !nearbyStoresPage.items.isEmpty
    }
}

struct HomeSectionMessages: Equatable, Sendable {
    let popularKeywords: String?
    let banners: String?
    let popularStores: String?
    let nearbyStores: String?

    static let none = HomeSectionMessages(
        popularKeywords: nil,
        banners: nil,
        popularStores: nil,
        nearbyStores: nil
    )
}

enum HomeFeedError: Error, Equatable {
    case authenticationRequired
    case configurationRequired(message: String)
    case unavailable(message: String)
}

extension HomeFeedError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .authenticationRequired:
            return "로그인이 필요합니다. 다시 로그인해 주세요."
        case .configurationRequired(let message), .unavailable(let message):
            return message
        }
    }
}

extension HomeFeedError {
    var blocksRetry: Bool {
        switch self {
        case .configurationRequired:
            return true
        case .authenticationRequired, .unavailable:
            return false
        }
    }
}
