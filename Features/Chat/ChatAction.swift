import CoreGraphics
import Foundation

enum ChatAction {
    case onAppear
    case onDisappear
    case refreshRequested
    case primaryButtonTapped
    case roomTapped(String)
    case backToRoomsTapped
    case messageTextChanged(String)
    case filesSelected([ChatUploadFile])
    case attachedFileRemoved(String)
    case sendMessageTapped
    case nearBottomChanged(Bool, distance: CGFloat)
    case newMessageIndicatorTapped
}
