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
    var replyThread: CommunityCommentThreadState?
    var emptyState: CommunityDetailEmptyState?
    var canManagePost = false
    var hasLoadedContent = false
    var isLoading = true
    var isDeletingPost = false
    var errorMessage: String?
}

struct CommunityCommentThreadState: Equatable {
    var parentComment: CommunityDetailCommentRowViewState
    var replies: [CommunityDetailCommentRowViewState]
    var draft = ""
    var isSubmitting = false
    var errorMessage: String?
    var requiresAuthentication = false
    var scrollTargetReplyID: String?

    var replyCountText: String {
        "답글 \(replies.count)개"
    }
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
    var highlightedCommentID: String?
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
    let authorID: String
    let authorName: String
    let authorAvatarPath: String?
    let canChatWithAuthor: Bool
    let timeText: String
    let content: String
    let isMine: Bool
    let isHidden: Bool
    let isPending: Bool
    let isFailed: Bool
    let depth: Int
    let replies: [CommunityDetailCommentRowViewState]

    var isTopLevel: Bool {
        depth == 0
    }
}
