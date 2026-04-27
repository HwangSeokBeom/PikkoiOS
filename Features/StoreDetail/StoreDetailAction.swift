import Foundation

enum StoreDetailAction {
    case onAppear
    case retryTapped
    case loginRequiredTapped
    case likeTapped
    case directionsTapped
    case chatTapped
    case menuFilterTapped(String)
    case menuIncrementTapped(String)
    case menuDecrementTapped(String)
    case reviewWriteTapped
    case reviewEditTapped
    case reviewDeleteTapped
    case stickyCTATapped
}
