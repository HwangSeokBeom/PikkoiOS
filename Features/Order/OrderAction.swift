import Foundation

enum OrderAction: Equatable {
    case onAppear
    case refreshRequested
    case retryTapped
    case filterTapped(OrderListFilter)
    case orderTapped(String)
    case orderAppeared(String)
    case loginRequiredTapped
    case exploreStoresTapped
}
