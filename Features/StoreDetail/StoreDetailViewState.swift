import Foundation

struct StoreDetailViewState: Equatable {
    var storeID = ""
    var storeName = ""
    var heroImages: [String] = []
    var isPicchelin = false
    var isLiked = false
    var ratingSummary = StoreDetailRatingSummary.placeholder
    var storeInfo = StoreDetailStoreInfo.placeholder
    var menuFilters = StoreDetailMenuFilter.defaults
    var selectedMenuFilter = StoreDetailMenuFilter.defaultOption
    var menus: [StoreDetailMenuItem] = []
    var menuSections: [StoreDetailMenuSection] = []
    var reviewPreview = StoreDetailReviewPreview.placeholder
    var reviewRatings: [StoreDetailReviewRatingBar] = []
    var stickyCartSummary = StoreDetailStickyCartSummary.placeholder
    var emptyState: StoreDetailEmptyState?
    var hasLoadedContent = false
    var isLoading = true
    var errorMessage: String?
    var successMessage: String?
    var reviewEligibilityMessage: String?
    var reviewEligibilityScrollTrigger = 0
}

struct StoreDetailEmptyState: Equatable {
    let title: String
    let message: String
    let actionTitle: String
    var requiresAuthentication = false
}

struct StoreDetailRatingSummary: Equatable {
    let likeCountText: String
    let ratingText: String
    let reviewCountText: String
    let orderCountText: String

    static let placeholder = StoreDetailRatingSummary(
        likeCountText: "0개",
        ratingText: "-",
        reviewCountText: "(0)",
        orderCountText: "누적 주문 0회"
    )
}

struct StoreDetailStoreInfo: Equatable {
    let address: String
    let operatingHours: String
    let parkingInfo: String
    let expectedPickupText: String
    let distanceText: String
    let descriptionText: String

    static let placeholder = StoreDetailStoreInfo(
        address: "",
        operatingHours: "",
        parkingInfo: "",
        expectedPickupText: "",
        distanceText: "",
        descriptionText: ""
    )
}

struct StoreDetailMenuFilter: Identifiable, Equatable {
    let id: String
    let title: String
    let systemImage: String?

    static let defaults: [StoreDetailMenuFilter] = [
        .init(id: "all", title: "전체메뉴", systemImage: "menucard.fill"),
        .init(id: "popular", title: "인기메뉴", systemImage: nil),
        .init(id: "signature", title: "시그니처", systemImage: nil)
    ]

    static let defaultOption = defaults[0]
}

struct StoreDetailMenuItem: Identifiable, Equatable {
    let id: String
    let badgeText: String?
    let name: String
    let description: String
    let priceText: String
    let imagePath: String?
    let isSoldOut: Bool
    let quantity: Int
    let filterIDs: [String]
}

struct StoreDetailMenuSection: Identifiable, Equatable {
    let id: String
    let title: String
    let subtitle: String?
    let items: [StoreDetailMenuItem]
}

struct StoreDetailReviewPreview: Equatable {
    let id: String?
    let title: String
    let body: String
    let keywordBadges: [String]
    let authorName: String
    let metricSummary: String
    let ratingText: String
    let showsActions: Bool

    static let placeholder = StoreDetailReviewPreview(
        id: nil,
        title: "",
        body: "",
        keywordBadges: [],
        authorName: "",
        metricSummary: "",
        ratingText: "-",
        showsActions: false
    )
}

struct StoreDetailReviewRatingBar: Identifiable, Equatable {
    let rating: Int
    let count: Int
    let ratio: Double

    var id: Int { rating }
}

struct StoreDetailStickyCartSummary: Equatable {
    let totalPriceText: String
    let itemCountText: String
    let buttonTitle: String
    let isEnabled: Bool

    static let placeholder = StoreDetailStickyCartSummary(
        totalPriceText: "0원",
        itemCountText: "0",
        buttonTitle: "메뉴를 담아주세요",
        isEnabled: false
    )
}
