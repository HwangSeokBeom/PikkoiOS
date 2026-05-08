import Foundation

enum ProfileAction {
    case onAppear
    case editProfileTapped
    case profileEditorDismissed
    case editorNickChanged(String)
    case editorPhoneNumberChanged(String)
    case profileImageDataSelected(Data, fileName: String)
    case profileImageSelectionFailed(String)
    case saveProfileTapped
    case likedStoresTapped
    case myPostsTapped
    case likedPostsTapped
    case myReviewsTapped
    case logoutTapped
}
