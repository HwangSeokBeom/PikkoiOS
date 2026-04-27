import Foundation

enum ChatAction {
    case onAppear
    case refreshRequested
    case primaryButtonTapped
    case roomTapped(String)
    case backToRoomsTapped
    case messageTextChanged(String)
    case sendMessageTapped
}
