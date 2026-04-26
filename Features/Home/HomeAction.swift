import Foundation

enum HomeAction {
    case onAppear
    case refreshRequested
    case loginRequiredTapped
    case locationTapped
    case searchTextChanged(String)
    case searchSubmitted
    case categoryTapped(String)
    case bannerTapped(String)
    case popularStoreTapped(String)
    case nearbyStoreTapped(String)
    case nearbyStoreAppeared(String)
    case likeTapped(String)
}
