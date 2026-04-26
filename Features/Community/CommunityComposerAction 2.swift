import Foundation

enum CommunityComposerAction {
    case onAppear
    case titleChanged(String)
    case bodyChanged(String)
    case categoryTapped(String)
    case attachmentsUploadRequested([CommunityPostUploadFile])
    case attachmentPreparationFailed(String)
    case attachmentRemoved(String)
    case submitTapped
}
