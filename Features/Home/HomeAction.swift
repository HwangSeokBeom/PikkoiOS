import Foundation

enum HomeAction {
    case onAppear
    case refreshRequested
    case loginRequiredTapped
    case locationTapped
    case currentLocationRequested
    case manualLocationSelectionTapped
    case selectedLocationSelected(PikkoSelectedLocation)
    case searchTextChanged(String)
    case searchSubmitted
    case popularKeywordTapped(String)
    case categoryTapped(String)
    case bannerTapped(id: String, index: Int)
    case nearbyStoreTabTapped(HomeNearbyStoreTab)
    case nearbyDistanceSortTapped
    case popularStoreTapped(String)
    case nearbyStoreTapped(String)
    case nearbyStoreAppeared(String)
    case likeTapped(String)
}
