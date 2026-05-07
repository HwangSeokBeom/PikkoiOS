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
    case filesSelected([ChatUploadFile])
    case attachedFileRemoved(String)
    case sendMessageTapped
    case nearBottomChanged(Bool, distance: CGFloat)
    case newMessageIndicatorTapped
}
