import Foundation

struct CommunityViewState {
    var searchText = ""
    var selectedSort: CommunitySort = .latest
    var sortCategories: [CommunitySortCategory] = CommunitySortCategory.allCases
    var selectedDistance: CommunityDistanceOption = .defaultOption
    var distanceOptions: [CommunityDistanceOption] = CommunityDistanceOption.all
    var filterChips: [CommunityFilter] = CommunityFilter.defaults
    var selectedFilterChipIDs: Set<String> = []
    var featuredBanner: CommunityFeaturedBanner?
    var posts: [CommunityCard.Model] = []
    var nextCursor: String?
    var emptyState: CommunityEmptyState?
    var feedStatus: CommunityFeedStatus = .loading
    var hasReferenceLocation = false
    var isLoading = true
    var isRefreshing = false
    var errorMessage: String?

    var selectedFilters: Set<CommunityFilter> {
        get { Set(selectedFilterChipIDs.compactMap(CommunityFilter.init(rawValue:))) }
        set {
            selectedFilterChipIDs = Set(newValue.map(\.id))
        }
    }
}
