import Foundation

struct HomeCategoryItem: Identifiable, Equatable {
    let id: String
    let title: String
    let imageName: String
    let fallbackSystemImage: String
    let apiValue: String?

    static let all: [HomeCategoryItem] = [
        HomeCategoryItem(
            id: "coffee",
            title: "커피",
            imageName: "HomeCategoryCoffee",
            fallbackSystemImage: "cup.and.saucer.fill",
            apiValue: "커피"
        ),
        HomeCategoryItem(
            id: "fastfood",
            title: "패스트푸드",
            imageName: "HomeCategoryFastfood",
            fallbackSystemImage: "takeoutbag.and.cup.and.straw.fill",
            apiValue: "패스트푸드"
        ),
        HomeCategoryItem(
            id: "dessert",
            title: "디저트",
            imageName: "HomeCategoryDessert",
            fallbackSystemImage: "birthday.cake.fill",
            apiValue: "디저트"
        ),
        HomeCategoryItem(
            id: "bakery",
            title: "베이커리",
            imageName: "HomeCategoryBakery",
            fallbackSystemImage: "basket.fill",
            apiValue: "베이커리"
        ),
        HomeCategoryItem(
            id: "all",
            title: "전체",
            imageName: "HomeCategoryAll",
            fallbackSystemImage: "sparkles",
            apiValue: nil
        )
    ]
}

struct HomeBannerItem: Identifiable, Equatable {
    let id: String
    let title: String
    let imagePath: String?
    let payloadType: String
    let payloadValue: String
}

enum HomeNearbyStoreTab: String, CaseIterable, Equatable {
    case nearby
    case realtimeDistance

    var title: String {
        switch self {
        case .nearby:
            return "주변 매장"
        case .realtimeDistance:
            return "실시간 거리"
        }
    }

    var systemImage: String? {
        switch self {
        case .nearby:
            return "location.circle.fill"
        case .realtimeDistance:
            return "figure.walk"
        }
    }
}

enum HomeNearbyStoreSortOrder: Equatable {
    case nearest
    case farthest

    mutating func toggle() {
        self = self == .nearest ? .farthest : .nearest
    }

    var title: String {
        switch self {
        case .nearest:
            return "거리순"
        case .farthest:
            return "먼거리순"
        }
    }

    var systemImage: String {
        switch self {
        case .nearest:
            return "arrow.up"
        case .farthest:
            return "arrow.down"
        }
    }
}

struct HomeViewState {
    var locationLabel = "현재 위치 주변"
    var searchText = ""
    var selectedCategory: HomeCategoryItem?
    var categories: [HomeCategoryItem] = HomeCategoryItem.all
    var popularKeywords: [String] = []
    var banners: [HomeBannerItem] = []
    var popularStores: [StoreCard.Model] = []
    var nearbyStores: [StoreCard.Model] = []
    var notificationUnreadCount = 0
    var popularKeywordsSectionMessage: String?
    var bannerSectionMessage: String?
    var popularStoresSectionMessage: String?
    var nearbyStoresSectionMessage: String?
    var selectedNearbyStoreTab: HomeNearbyStoreTab = .nearby
    var nearbyStoreSortOrder: HomeNearbyStoreSortOrder = .nearest
    var nearbyDistanceSortTitle: String { nearbyStoreSortOrder.title }
    var nearbyDistanceSortSystemImage: String { nearbyStoreSortOrder.systemImage }
    var nextCursor: String?
    var emptyState: HomeEmptyState?
    var isLoading = true
    var isRefreshing = false
    var errorMessage: String?
}

struct HomeEmptyState: Equatable {
    let title: String
    let message: String
    let actionTitle: String?
    var requiresAuthentication = false
}
