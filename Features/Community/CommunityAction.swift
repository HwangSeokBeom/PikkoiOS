import Foundation

enum CommunityAction {
    case onAppear
    case refreshRequested
    case loginRequiredTapped
    case searchTextChanged(String)
    case searchSubmitted
    case composeTapped
    case sortSelected(String)
    case distanceSelected(String)
    case filterChipTapped(String)
    case postTapped(String)
    case storeSnippetTapped(String)
    case postAppeared(String)
    case likeTapped(String)
}
