import Foundation

struct CommunityDetailViewState: Equatable {
    let postID: String
    var heroEyebrow = ""
    var heroTitle = ""
    var heroMessage = ""
    var postCard: CommunityCard.Model?
    var footerTitle = ""
    var footerMessage = ""
    var commentSection = CommunityDetailCommentSectionState()
    var emptyState: CommunityDetailEmptyState?
    var canManagePost = false
    var hasLoadedContent = false
    var isLoading = true
    var isDeletingPost = false
    var errorMessage: String?
}

struct CommunityDetailEmptyState: Equatable {
    let title: String
    let message: String
    let actionTitle: String
    var requiresAuthentication = false
}

struct CommunityDetailCommentSectionState: Equatable {
    var countText = "댓글 0개"
    var comments: [CommunityDetailCommentRowViewState] = []
    var isInitialLoading = false
    var isLoadingMore = false
    var canLoadMore = false
    var nextCursor: String?
    var errorMessage: String?
    var isSubmittingComment = false
    var composerText = ""
    var editingCommentID: String?
    var editingDraftText = ""
    var emptyState: CommunityDetailCommentEmptyState?
    var requiresAuthentication = false
}

struct CommunityDetailCommentEmptyState: Equatable {
    let title: String
    let message: String
    let actionTitle: String
    var requiresAuthentication = false
}

struct CommunityDetailCommentRowViewState: Equatable, Identifiable {
    let id: String
    let authorName: String
    let authorAvatarPath: String?
    let timeText: String
    let content: String
    let isMine: Bool
    let isHidden: Bool
    let depth: Int
    let replies: [CommunityDetailCommentRowViewState]
}
