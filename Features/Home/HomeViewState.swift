import Foundation

struct HomeCategoryItem: Identifiable, Equatable {
    let id: String
    let title: String
    let icon: String
    let apiValue: String?

    static let all: [HomeCategoryItem] = [
        HomeCategoryItem(id: "coffee", title: "커피", icon: "☕️", apiValue: "커피"),
        HomeCategoryItem(id: "fastfood", title: "패스트푸드", icon: "🍔", apiValue: "패스트푸드"),
        HomeCategoryItem(id: "dessert", title: "디저트", icon: "🧁", apiValue: "디저트"),
        HomeCategoryItem(id: "bakery", title: "베이커리", icon: "🥐", apiValue: "베이커리"),
        HomeCategoryItem(id: "all", title: "전체", icon: "✨", apiValue: nil)
    ]
}

struct HomeBannerItem: Identifiable, Equatable {
    let id: String
    let title: String
    let imagePath: String?
    let payloadType: String
    let payloadValue: String
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
    var popularKeywordsSectionMessage: String?
    var bannerSectionMessage: String?
    var popularStoresSectionMessage: String?
    var nearbyStoresSectionMessage: String?
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
