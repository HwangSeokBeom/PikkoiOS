import Foundation

struct CommunityComposerViewState: Equatable {
    var mode: CommunityComposerMode = .create
    var navigationTitle = "글 작성"
    var eyebrow = ""
    var heroTitle = ""
    var heroMessage = ""
    var titlePlaceholder = ""
    var bodyPlaceholder = ""
    var footerTitle = ""
    var footerMessage = ""
    var submitTitle = "등록"
    var categoryOptions: [CommunityComposerCategoryOption] = []
    var selectedCategoryID: String?
    var draftTitle = ""
    var draftBody = ""
    var linkedStoreTitle: String?
    var attachmentCount = 0
    var attachmentPaths: [String] = []
    var submittedPostID: String?
    var infoMessage: String?
    var hasLoadedContent = false
    var isLoading = true
    var isUploadingAttachments = false
    var isSubmitting = false
    var errorMessage: String?
    var serverValidationMessage: String?
    var attachmentUploadErrorMessage: String?

    var isSubmitEnabled: Bool {
        selectedCategoryID != nil &&
        !draftTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !draftBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !isUploadingAttachments &&
        attachmentUploadErrorMessage == nil &&
        !isSubmitting
    }
}
