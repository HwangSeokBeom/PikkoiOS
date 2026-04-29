import Foundation

enum OrderAction: Equatable {
    case onAppear
    case refreshRequested
    case retryTapped
    case filterTapped(OrderListFilter)
    case orderTapped(String)
    case cancelConfirmed(String)
    case statusSelected(orderCode: String, currentStatus: OrderStatus, nextStatus: OrderStatus)
    case statusChangeConfirmed(orderCode: String, nextStatus: OrderStatus)
    case orderAppeared(String)
    case loginRequiredTapped
    case exploreStoresTapped
}
