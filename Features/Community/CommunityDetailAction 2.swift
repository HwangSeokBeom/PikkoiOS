import Foundation

enum CommunityDetailAction {
    case onAppear
    case retryTapped
    case postEditTapped
    case postDeleteConfirmed
    case commentsRetryTapped
    case loginRequiredTapped
    case likeTapped
    case storeSnippetTapped(String)
    case commentComposerChanged(String)
    case commentSubmitTapped
    case commentLoadMoreIfNeeded(String)
    case commentEditTapped(String)
    case commentEditDraftChanged(String)
    case commentEditSaveTapped
    case commentEditCancelled
    case commentDeleteConfirmed(String)
}
