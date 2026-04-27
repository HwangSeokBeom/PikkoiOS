import Foundation

struct CommunityViewState {
    var searchText = ""
    var selectedSort: CommunitySortOption = .latest
    var selectedDistance: CommunityDistanceOption = .defaultOption
    var sortOptions: [CommunitySortOption] = CommunitySortOption.all
    var distanceOptions: [CommunityDistanceOption] = CommunityDistanceOption.all
    var filterChips: [CommunityFilterChip] = CommunityFilterChip.defaults
    var selectedFilterChipIDs: Set<String> = []
    var featuredBanner: CommunityFeaturedBanner?
    var posts: [CommunityCard.Model] = []
    var nextCursor: String?
    var emptyState: CommunityEmptyState?
    var feedStatus: CommunityFeedStatus = .loading
    var isLoading = true
    var isRefreshing = false
    var errorMessage: String?
}
