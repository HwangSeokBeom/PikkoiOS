import Foundation

@MainActor
final class CommunityDetailPresenter: ObservableObject {
    @Published private(set) var viewState: CommunityDetailViewState

    private let interactor: CommunityDetailInteracting
    private let router: CommunityDetailRouting
    private let sessionStore: SessionStore
    private let distanceFormatter = DistanceFormatter()
    private let relativeDateFormatter = RelativeDateTimeFormatter()

    private var hasLoaded = false
    private var detail: CommunityPostDetail?
    private var distanceMeters: Double?
    private var comments: [CommunityComment] = []
    private var nextCommentCursor: String?
    private var isLoadingMoreComments = false
    private var isUpdatingLikeStatus = false

    init(
        postID: String,
        interactor: CommunityDetailInteracting,
        router: CommunityDetailRouting,
        sessionStore: SessionStore
    ) {
        self.interactor = interactor
        self.router = router
        self.sessionStore = sessionStore
        self.viewState = CommunityDetailViewState(postID: postID)
        self.relativeDateFormatter.locale = Locale(identifier: "ko_KR")
        self.relativeDateFormatter.unitsStyle = .full
    }

    func send(_ action: CommunityDetailAction) async {
        switch action {
        case .onAppear:
            guard !hasLoaded else { return }
            await loadInitialContent()
        case .retryTapped:
            await loadInitialContent()
        case .postEditTapped:
            routeToPostEditor()
        case .postDeleteConfirmed:
            await deletePost()
        case .commentsRetryTapped:
            await loadComments(reset: true)
        case .loginRequiredTapped:
            routeToCommentAuth(message: "댓글을 작성하려면 로그인이 필요합니다.")
        case .likeTapped:
            await toggleLikeStatus()
        case .authorChatTapped(let authorID):
            routeToAuthorChat(authorID: authorID)
        case .commentAuthorChatTapped(let authorID):
            routeToCommentAuthorChat(authorID: authorID)
        case .storeSnippetTapped(let storeID):
            router.routeToStoreDetail(storeID: storeID)
        case .commentComposerChanged(let text):
            viewState.commentSection.composerText = text
            if viewState.commentSection.errorMessage != nil,
               !viewState.commentSection.requiresAuthentication {
                viewState.commentSection.errorMessage = nil
            }
            syncCommentSectionState()
        case .commentSubmitTapped:
            await submitComment()
        case .commentLoadMoreIfNeeded(let lastVisibleCommentID):
            await loadMoreCommentsIfNeeded(lastVisibleCommentID: lastVisibleCommentID)
        case .commentEditTapped(let commentID):
            beginEditingComment(commentID: commentID)
        case .commentEditDraftChanged(let draft):
            viewState.commentSection.editingDraftText = draft
        case .commentEditSaveTapped:
            await saveEditedComment()
        case .commentEditCancelled:
            cancelEditingComment()
        case .commentDeleteConfirmed(let commentID):
            await deleteComment(commentID: commentID)
        }
    }

    private func loadInitialContent() async {
        viewState.isLoading = true
        viewState.errorMessage = nil
        viewState.emptyState = nil

        do {
            let content = try await interactor.loadInitialContent()
            apply(content: content)
            hasLoaded = true
            viewState.isLoading = false
            await loadComments(reset: true)
        } catch {
            viewState.hasLoadedContent = false
            detail = nil
            distanceMeters = nil
            comments = []
            resetCommentSection()
            viewState.errorMessage = resolveErrorMessage(from: error)
            viewState.emptyState = makeEmptyState(for: error)
            viewState.isLoading = false
        }
    }

    private func apply(content: CommunityDetailContent) {
        detail = content.detail
        distanceMeters = content.distanceMeters
        comments = content.detail.comments
        nextCommentCursor = nil

        viewState.errorMessage = nil
        viewState.hasLoadedContent = true
        viewState.emptyState = nil
        viewState.commentSection.errorMessage = nil
        viewState.commentSection.requiresAuthentication = false
        syncAllViewState()
    }

    private func loadComments(reset: Bool) async {
        guard detail != nil else { return }

        if reset {
            viewState.commentSection.isInitialLoading = comments.isEmpty
            viewState.commentSection.errorMessage = nil
            viewState.commentSection.requiresAuthentication = false
            syncCommentSectionState()
        } else {
            guard !isLoadingMoreComments,
                  viewState.commentSection.canLoadMore,
                  let nextCommentCursor else {
                return
            }

            isLoadingMoreComments = true
            viewState.commentSection.isLoadingMore = true
            viewState.commentSection.errorMessage = nil
            syncCommentSectionState()

            do {
                let page = try await interactor.loadComments(nextCursor: nextCommentCursor)
                comments = appendUniqueComments(existing: comments, incoming: page.items)
                self.nextCommentCursor = page.nextCursor
                syncDetailComments()
                viewState.commentSection.isLoadingMore = false
                isLoadingMoreComments = false
                syncAllViewState()
            } catch {
                viewState.commentSection.isLoadingMore = false
                isLoadingMoreComments = false
                applyCommentFailure(error)
            }

            return
        }

        do {
            let page = try await interactor.loadComments(nextCursor: nil)
            comments = page.items
            nextCommentCursor = page.nextCursor
            syncDetailComments()
            viewState.commentSection.isInitialLoading = false
            syncAllViewState()
        } catch {
            nextCommentCursor = nil
            viewState.commentSection.isInitialLoading = false
            applyCommentFailure(error)
        }
    }

    private func loadMoreCommentsIfNeeded(lastVisibleCommentID: String) async {
        guard viewState.commentSection.comments.last?.id == lastVisibleCommentID else {
            return
        }

        await loadComments(reset: false)
    }

    private func toggleLikeStatus() async {
        guard !isUpdatingLikeStatus else { return }
        guard let currentDetail = detail else { return }

        isUpdatingLikeStatus = true
        defer { isUpdatingLikeStatus = false }

        let currentSummary = currentDetail.summary
        let optimisticLikeStatus = !currentSummary.isLiked
        let previousDetail = currentDetail

        detail = CommunityPostDetail(
            summary: makeUpdatedSummary(
                from: currentSummary,
                isLiked: optimisticLikeStatus
            ),
            comments: comments
        )
        syncAllViewState()

        do {
            let confirmedStatus = try await interactor.updateLikeStatus(isLiked: optimisticLikeStatus)
            detail = CommunityPostDetail(
                summary: makeUpdatedSummary(
                    from: currentSummary,
                    isLiked: confirmedStatus
                ),
                comments: comments
            )
            syncAllViewState()
            if let updatedSummary = detail?.summary {
                postCommunityChange(summary: updatedSummary)
            }
        } catch {
            detail = previousDetail
            syncAllViewState()
            viewState.errorMessage = resolveErrorMessage(from: error)
        }
    }

    private func submitComment() async {
        guard !viewState.commentSection.isSubmittingComment else { return }
        guard ensureAuthenticatedForCommentAction(
            message: "댓글을 작성하려면 로그인이 필요합니다."
        ) else {
            return
        }

        let draft = viewState.commentSection.composerText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !draft.isEmpty else {
            setCommentError(
                message: "댓글 내용을 입력해 주세요.",
                requiresAuthentication: false
            )
            return
        }

        viewState.commentSection.isSubmittingComment = true
        syncCommentSectionState()
        #if DEBUG
        Logger.shared.debug("[CommunityComment] submit postID=\(viewState.postID)")
        #endif

        do {
            let createdComment = try await interactor.createComment(content: draft)
            comments = prependComment(createdComment, to: comments)
            viewState.commentSection.composerText = ""
            viewState.commentSection.errorMessage = nil
            viewState.commentSection.requiresAuthentication = false
            viewState.commentSection.isSubmittingComment = false
            syncDetailComments()
            syncAllViewState()
            if let detail {
                postCommunityChange(summary: detail.summary)
            }
            #if DEBUG
            Logger.shared.debug("[CommunityComment] success commentID=\(createdComment.id)")
            #endif
        } catch {
            viewState.commentSection.isSubmittingComment = false
            applyCommentFailure(error)
        }
    }

    private func beginEditingComment(commentID: String) {
        guard let comment = findComment(commentID, in: comments),
              comment.isMine else {
            return
        }

        viewState.commentSection.editingCommentID = commentID
        viewState.commentSection.editingDraftText = comment.content
        viewState.commentSection.errorMessage = nil
    }

    private func cancelEditingComment() {
        viewState.commentSection.editingCommentID = nil
        viewState.commentSection.editingDraftText = ""
    }

    private func saveEditedComment() async {
        guard !viewState.commentSection.isSubmittingComment,
              let editingCommentID = viewState.commentSection.editingCommentID else {
            return
        }
        guard ensureAuthenticatedForCommentAction(
            message: "댓글을 수정하려면 로그인이 필요합니다."
        ) else {
            return
        }

        let draft = viewState.commentSection.editingDraftText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !draft.isEmpty else {
            setCommentError(
                message: "댓글 내용을 입력해 주세요.",
                requiresAuthentication: false
            )
            return
        }

        viewState.commentSection.isSubmittingComment = true
        syncCommentSectionState()

        do {
            let updatedComment = try await interactor.updateComment(
                commentID: editingCommentID,
                content: draft
            )
            comments = replaceComment(
                updatedComment,
                in: comments
            )
            viewState.commentSection.isSubmittingComment = false
            viewState.commentSection.editingCommentID = nil
            viewState.commentSection.editingDraftText = ""
            viewState.commentSection.errorMessage = nil
            syncDetailComments()
            syncAllViewState()
            if let detail {
                postCommunityChange(summary: detail.summary)
            }
        } catch {
            viewState.commentSection.isSubmittingComment = false
            applyCommentFailure(error)
        }
    }

    private func deleteComment(commentID: String) async {
        guard !viewState.commentSection.isSubmittingComment else { return }
        guard ensureAuthenticatedForCommentAction(
            message: "댓글을 삭제하려면 로그인이 필요합니다."
        ) else {
            return
        }

        viewState.commentSection.isSubmittingComment = true
        syncCommentSectionState()

        do {
            try await interactor.deleteComment(commentID: commentID)
            comments = removeComment(commentID, from: comments)
            if viewState.commentSection.editingCommentID == commentID {
                viewState.commentSection.editingCommentID = nil
                viewState.commentSection.editingDraftText = ""
            }
            viewState.commentSection.isSubmittingComment = false
            viewState.commentSection.errorMessage = nil
            syncDetailComments()
            syncAllViewState()
            if let detail {
                postCommunityChange(summary: detail.summary)
            }
        } catch {
            viewState.commentSection.isSubmittingComment = false
            applyCommentFailure(error)
        }
    }

    private func syncDetailComments() {
        guard let currentDetail = detail else { return }
        detail = CommunityPostDetail(
            summary: currentDetail.summary,
            comments: comments
        )
    }

    private func syncAllViewState() {
        guard let detail else { return }
        applyDetailViewState(detail: detail, distanceMeters: distanceMeters)
        syncCommentSectionState()
    }

    private func applyDetailViewState(
        detail: CommunityPostDetail,
        distanceMeters: Double?
    ) {
        viewState.heroEyebrow = detail.summary.category ?? "커뮤니티"
        viewState.heroTitle = detail.summary.title
        viewState.heroMessage = makeHeroMessage(
            from: detail,
            comments: comments
        )
        viewState.postCard = makePostCardModel(
            from: detail.summary,
            distanceMeters: distanceMeters
        )
        viewState.footerTitle = makeFooterTitle(from: comments)
        viewState.footerMessage = makeFooterMessage(from: comments)
        viewState.canManagePost = detail.summary.creator.id == sessionStore.currentUserID
    }

    private func syncCommentSectionState() {
        viewState.commentSection.comments = comments.map { makeCommentRowState(from: $0, depth: 0) }
        viewState.commentSection.countText = "댓글 \(comments.reduce(0) { $0 + $1.totalCountIncludingReplies })개"
        viewState.commentSection.nextCursor = nextCommentCursor
        viewState.commentSection.canLoadMore = nextCommentCursor != nil

        if comments.isEmpty && !viewState.commentSection.isInitialLoading {
            if viewState.commentSection.requiresAuthentication {
                viewState.commentSection.emptyState = CommunityDetailCommentEmptyState(
                    title: "로그인이 필요해요",
                    message: "댓글을 작성하려면 로그인해 주세요.",
                    actionTitle: "로그인하러 가기",
                    requiresAuthentication: true
                )
            } else if let errorMessage = viewState.commentSection.errorMessage {
                viewState.commentSection.emptyState = CommunityDetailCommentEmptyState(
                    title: "댓글을 불러오지 못했어요",
                    message: errorMessage,
                    actionTitle: "다시 시도"
                )
            } else {
                viewState.commentSection.emptyState = CommunityDetailCommentEmptyState(
                    title: "댓글이 아직 없어요",
                    message: "이 게시글의 첫 댓글을 남겨보세요.",
                    actionTitle: "새로고침"
                )
            }
        } else {
            viewState.commentSection.emptyState = nil
        }
    }

    private func resetCommentSection() {
        viewState.commentSection = CommunityDetailCommentSectionState()
        comments = []
        nextCommentCursor = nil
        isLoadingMoreComments = false
    }

    private func applyCommentFailure(_ error: Error) {
        let message = resolveCommentErrorMessage(from: error)
        let requiresAuthentication = isCommentAuthenticationFailure(error)
        if requiresAuthentication {
            router.routeToAuth(context: .communityComment)
        }
        setCommentError(
            message: message,
            requiresAuthentication: requiresAuthentication
        )
    }

    private func ensureAuthenticatedForCommentAction(message: String) -> Bool {
        guard sessionStore.isAuthenticated else {
            routeToCommentAuth(message: message)
            return false
        }

        return true
    }

    private func routeToCommentAuth(message: String) {
        setCommentError(
            message: message,
            requiresAuthentication: true
        )
        router.routeToAuth(context: .communityComment)
    }

    private func routeToPostEditor() {
        guard let detail,
              detail.summary.creator.id == sessionStore.currentUserID else {
            viewState.errorMessage = "작성자만 수정/삭제할 수 있습니다."
            return
        }

        router.routeToComposer(
            mode: .edit(postID: detail.summary.id),
            initialDraft: makeInitialDraft(from: detail.summary)
        )
    }

    private func routeToAuthorChat(authorID: String) {
        guard sessionStore.isAuthenticated else {
            routeToCommentAuth(message: "채팅을 시작하려면 로그인이 필요합니다.")
            return
        }
        guard let summary = detail?.summary,
              summary.creator.id == authorID,
              authorID != sessionStore.currentUserID else {
            viewState.errorMessage = "채팅 상대를 찾지 못했어요."
            return
        }
        router.routeToChat(
            target: .user(
                userID: summary.creator.id,
                nickname: summary.creator.nick,
                profileImagePath: summary.creator.profileImagePath
            )
        )
    }

    private func routeToCommentAuthorChat(authorID: String) {
        guard sessionStore.isAuthenticated else {
            routeToCommentAuth(message: "채팅을 시작하려면 로그인이 필요합니다.")
            return
        }
        guard let author = findCommentAuthor(id: authorID, in: comments),
              author.id != sessionStore.currentUserID else {
            viewState.commentSection.errorMessage = "채팅 상대를 찾지 못했어요."
            return
        }
        router.routeToChat(
            target: .user(
                userID: author.id,
                nickname: author.nick,
                profileImagePath: author.profileImagePath
            )
        )
    }

    private func findCommentAuthor(id: String, in comments: [CommunityComment]) -> CommunityPostAuthor? {
        for comment in comments {
            if comment.author.id == id {
                return comment.author
            }
            if let author = findCommentAuthor(id: id, in: comment.replies) {
                return author
            }
        }
        return nil
    }

    private func deletePost() async {
        guard !viewState.isDeletingPost else { return }
        guard let detail else { return }

        guard detail.summary.creator.id == sessionStore.currentUserID else {
            viewState.errorMessage = "작성자만 수정/삭제할 수 있습니다."
            return
        }

        viewState.isDeletingPost = true
        viewState.errorMessage = nil

        do {
            try await interactor.deletePost()
            viewState.isDeletingPost = false
            router.requestDismiss()
        } catch {
            viewState.isDeletingPost = false
            viewState.errorMessage = resolveErrorMessage(from: error)
        }
    }

    private func setCommentError(
        message: String,
        requiresAuthentication: Bool
    ) {
        viewState.commentSection.errorMessage = message
        viewState.commentSection.requiresAuthentication = requiresAuthentication
        syncCommentSectionState()
    }

    private func makeUpdatedSummary(
        from summary: CommunityPostSummary,
        isLiked: Bool
    ) -> CommunityPostSummary {
        let likeDelta: Int
        switch (summary.isLiked, isLiked) {
        case (false, true):
            likeDelta = 1
        case (true, false):
            likeDelta = -1
        default:
            likeDelta = 0
        }

        return CommunityPostSummary(
            id: summary.id,
            category: summary.category,
            title: summary.title,
            content: summary.content,
            creator: summary.creator,
            mediaPaths: summary.mediaPaths,
            store: summary.store,
            isLiked: isLiked,
            likeCount: max(summary.likeCount + likeDelta, 0),
            longitude: summary.longitude,
            latitude: summary.latitude,
            createdAt: summary.createdAt,
            updatedAt: summary.updatedAt
        )
    }

    private func postCommunityChange(summary: CommunityPostSummary) {
        let event = CommunityPostChangeNotification(
            postID: summary.id,
            isLiked: summary.isLiked,
            likeCount: summary.likeCount,
            commentCount: comments.reduce(0) { $0 + $1.totalCountIncludingReplies }
        )
        NotificationCenter.default.post(
            name: .pikkoCommunityPostDidChange,
            object: nil,
            userInfo: [CommunityPostChangeNotificationUserInfoKey.event: event]
        )
    }

    private func makeInitialDraft(from summary: CommunityPostSummary) -> CommunityComposerInitialDraft {
        CommunityComposerInitialDraft(
            title: summary.title,
            body: summary.content,
            categoryTitle: summary.category,
            store: summary.store.map {
                .init(id: $0.id, name: $0.name)
            },
            attachments: summary.mediaPaths.map {
                .init(path: normalizeAttachmentPathForRequest($0))
            },
            latitude: summary.latitude,
            longitude: summary.longitude
        )
    }

    private func normalizeAttachmentPathForRequest(_ path: String) -> String {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return trimmed
        }

        if let absoluteURL = URL(string: trimmed),
           let scheme = absoluteURL.scheme,
           !scheme.isEmpty {
            let resolvedPath = absoluteURL.path
            if resolvedPath.hasPrefix("/v1/data/") {
                return String(resolvedPath.dropFirst(3))
            }
            return resolvedPath
        }

        if trimmed.hasPrefix("/v1/data/") {
            return String(trimmed.dropFirst(3))
        }

        return trimmed
    }

    private func makePostCardModel(
        from summary: CommunityPostSummary,
        distanceMeters: Double?
    ) -> CommunityCard.Model {
        CommunityCard.Model(
            id: summary.id,
            authorID: summary.creator.id,
            authorName: summary.creator.nick,
            authorAvatarPath: summary.creator.profileImagePath,
            canChatWithAuthor: summary.creator.id != sessionStore.currentUserID,
            timeText: makeRelativeTimeText(from: summary.createdAt),
            title: summary.title,
            bodyText: summary.content,
            likeText: "\(summary.likeCount)개",
            distanceText: makeDistanceText(from: distanceMeters),
            media: summary.mediaPaths.enumerated().map { index, path in
                .init(id: "\(summary.id)-media-\(index)", path: path)
            },
            storeSnippet: summary.store.map {
                .init(
                    id: $0.id,
                    title: $0.name,
                    subtitle: makeStoreSubtitle(from: $0),
                    imagePath: $0.imagePaths.first
                )
            },
            isLiked: summary.isLiked
        )
    }

    private func makeHeroMessage(
        from detail: CommunityPostDetail,
        comments: [CommunityComment]
    ) -> String {
        let timeText = makeRelativeTimeText(from: detail.summary.createdAt)
        let commentCount = comments.reduce(0) { $0 + $1.totalCountIncludingReplies }
        let commentText = commentCount == 0 ? "아직 댓글 없음" : "댓글 \(commentCount)개"
        return "\(detail.summary.creator.nick) · \(timeText) · \(commentText)"
    }

    private func makeFooterTitle(from comments: [CommunityComment]) -> String {
        if comments.isEmpty {
            return "첫 댓글을 기다리고 있어요"
        }

        return "댓글 미리보기"
    }

    private func makeFooterMessage(from comments: [CommunityComment]) -> String {
        guard let firstComment = comments.first else {
            return "아직 등록된 댓글이 없어요. 아래 입력창에서 첫 댓글을 남길 수 있어요."
        }

        let replySuffix = firstComment.replies.isEmpty ? "" : " · 답글 \(firstComment.replies.count)개"
        return "\(firstComment.author.nick): \(firstComment.content)\(replySuffix)"
    }

    private func makeCommentRowState(
        from comment: CommunityComment,
        depth: Int
    ) -> CommunityDetailCommentRowViewState {
        CommunityDetailCommentRowViewState(
            id: comment.id,
            authorID: comment.author.id,
            authorName: comment.author.nick,
            authorAvatarPath: comment.author.profileImagePath,
            canChatWithAuthor: !comment.isMine && !comment.isHidden,
            timeText: makeRelativeTimeText(from: comment.updatedAt ?? comment.createdAt),
            content: comment.isHidden ? "삭제된 댓글입니다." : comment.content,
            isMine: comment.isMine,
            isHidden: comment.isHidden,
            depth: depth,
            replies: comment.replies.map { makeCommentRowState(from: $0, depth: depth + 1) }
        )
    }

    private func appendUniqueComments(
        existing: [CommunityComment],
        incoming: [CommunityComment]
    ) -> [CommunityComment] {
        var ids = Set(existing.map(\.id))
        var merged = existing

        for comment in incoming where !ids.contains(comment.id) {
            ids.insert(comment.id)
            merged.append(comment)
        }

        return merged
    }

    private func prependComment(
        _ comment: CommunityComment,
        to comments: [CommunityComment]
    ) -> [CommunityComment] {
        [comment] + comments.filter { $0.id != comment.id }
    }

    private func replaceComment(
        _ updatedComment: CommunityComment,
        in comments: [CommunityComment]
    ) -> [CommunityComment] {
        comments.map { comment in
            if comment.id == updatedComment.id {
                return CommunityComment(
                    id: updatedComment.id,
                    postID: updatedComment.postID,
                    parentCommentID: comment.parentCommentID ?? updatedComment.parentCommentID,
                    author: updatedComment.author,
                    content: updatedComment.content,
                    createdAt: updatedComment.createdAt ?? comment.createdAt,
                    updatedAt: updatedComment.updatedAt ?? updatedComment.createdAt ?? comment.updatedAt,
                    isMine: updatedComment.isMine || comment.isMine,
                    isHidden: updatedComment.isHidden,
                    replies: comment.replies
                )
            }

            guard !comment.replies.isEmpty else {
                return comment
            }

            return CommunityComment(
                id: comment.id,
                postID: comment.postID,
                parentCommentID: comment.parentCommentID,
                author: comment.author,
                content: comment.content,
                createdAt: comment.createdAt,
                updatedAt: comment.updatedAt,
                isMine: comment.isMine,
                isHidden: comment.isHidden,
                replies: replaceComment(updatedComment, in: comment.replies)
            )
        }
    }

    private func removeComment(
        _ commentID: String,
        from comments: [CommunityComment]
    ) -> [CommunityComment] {
        comments.compactMap { comment in
            guard comment.id != commentID else {
                return nil
            }

            return CommunityComment(
                id: comment.id,
                postID: comment.postID,
                parentCommentID: comment.parentCommentID,
                author: comment.author,
                content: comment.content,
                createdAt: comment.createdAt,
                updatedAt: comment.updatedAt,
                isMine: comment.isMine,
                isHidden: comment.isHidden,
                replies: removeComment(commentID, from: comment.replies)
            )
        }
    }

    private func findComment(
        _ commentID: String,
        in comments: [CommunityComment]
    ) -> CommunityComment? {
        for comment in comments {
            if comment.id == commentID {
                return comment
            }

            if let reply = findComment(commentID, in: comment.replies) {
                return reply
            }
        }

        return nil
    }

    private func makeDistanceText(from distanceMeters: Double?) -> String {
        guard let distanceMeters else {
            return "-"
        }

        return distanceFormatter.string(fromMeters: distanceMeters)
    }

    private func makeRelativeTimeText(from date: Date?) -> String {
        guard let date else {
            return "방금 전"
        }

        let relativeText = relativeDateFormatter.localizedString(for: date, relativeTo: Date())
        if relativeText.hasPrefix("in ") || relativeText.hasPrefix("후") {
            return "방금 전"
        }
        return relativeText
    }

    private func makeStoreSubtitle(from store: CommunityPostStoreSummary) -> String {
        let categoryText = store.category ?? "가게"

        if let closeTime = store.closeTime, !closeTime.isEmpty {
            return "\(categoryText) · 마감 \(closeTime)"
        }

        return categoryText
    }

    private func makeEmptyState(for error: Error) -> CommunityDetailEmptyState {
        if let featureError = error as? CommunityDetailFeatureError {
            switch featureError {
            case .authenticationRequired:
                return CommunityDetailEmptyState(
                    title: "로그인이 필요해요",
                    message: "게시글 상세는 로그인 후 확인할 수 있어요.",
                    actionTitle: "로그인하러 가기",
                    requiresAuthentication: true
                )
            case .notFound(let message):
                return CommunityDetailEmptyState(
                    title: "게시글을 찾을 수 없어요",
                    message: message,
                    actionTitle: "다시 시도"
                )
            case .unavailable(let message):
                return CommunityDetailEmptyState(
                    title: "게시글 상세를 불러오지 못했어요",
                    message: message,
                    actionTitle: "다시 시도"
                )
            }
        }

        return CommunityDetailEmptyState(
            title: "게시글 상세를 불러오지 못했어요",
            message: "postID=\(viewState.postID) 기준 상세 화면은 열렸지만 데이터를 준비하지 못했어요. 잠시 후 다시 시도해 주세요.",
            actionTitle: "다시 시도"
        )
    }

    private func resolveErrorMessage(from error: Error) -> String {
        if let localizedError = error as? LocalizedError,
           let description = localizedError.errorDescription,
           !description.isEmpty {
            return description
        }

        return error.localizedDescription
    }

    private func resolveCommentErrorMessage(from error: Error) -> String {
        if let localizedError = error as? LocalizedError,
           let description = localizedError.errorDescription,
           !description.isEmpty {
            return description
        }

        return error.localizedDescription
    }

    private func isCommentAuthenticationFailure(_ error: Error) -> Bool {
        if let commentError = error as? CommunityDetailCommentFeatureError,
           case .authenticationRequired = commentError {
            return true
        }

        if let networkError = error as? NetworkError {
            return networkError.isAuthenticationFailure
        }

        return false
    }
}
