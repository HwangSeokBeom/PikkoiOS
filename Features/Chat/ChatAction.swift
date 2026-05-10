import CoreGraphics
import Foundation

enum ChatAction {
    case onAppear(instanceID: String, presentationKind: ChatPresentationKind)
    case onDisappear(instanceID: String, presentationKind: ChatPresentationKind)
    case refreshRequested
    case primaryButtonTapped
    case roomTapped(String)
    case backToRoomsTapped
    case messageTextChanged(String)
    case roomListSearchQueryChanged(String)
    case searchTapped
    case searchDismissed
    case searchQueryChanged(String)
    case nextSearchResultTapped
    case previousSearchResultTapped
    case searchResultTapped(String)
    case filesSelected([ChatUploadFile])
    case fileSelectionFailed(String)
    case attachedFileRemoved(String)
    case sendMessageTapped
    case roomListReachedEnd
    case nearBottomChanged(Bool, distance: CGFloat)
    case newMessageIndicatorTapped
}
