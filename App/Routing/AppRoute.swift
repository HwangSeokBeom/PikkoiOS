import Foundation

enum AppRoute: Equatable {
    case home
    case storeDetail(storeID: String)
    case cart
    case checkout
    case orderHistory
    case profile
    case community
    case chat
}
