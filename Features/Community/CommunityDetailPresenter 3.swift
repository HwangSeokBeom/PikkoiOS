import Foundation

@MainActor
final class CommunityDetailPresenter: ObservableObject {
    @Published private(set) var viewState: CommunityDetailViewState

    private let interactor: CommunityDetailInteracting
    private let router: CommunityDetailRouting
    private let distanceFormatter = DistanceFormatter()
    private let relativeDateFormatter = RelativeDateTimeFormatter()
    private var hasLoaded = false
    private var detail: CommunityPostDetail?
    private var distanceMeters: Double?

    init(
        postID: String,
        interactor: CommunityDetailInteracting,
        router: CommunityDetailRouting
    ) {
        self.interactor = interactor
        self.router = router
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
        case .loginRequiredTapped:
            router.routeToAuth()
        case .likeTapped:
            await toggleLikeStatus()
        case .storeSnippetTapped(let storeID):
            router.routeToStoreDetail(storeID: storeID)
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
        } catch {
            viewState.hasLoadedContent = false
            detail = nil
            distanceMeters = nil
            viewState.errorMessage = resolveErrorMessage(from: error)
            viewState.emptyState = makeEmptyState(for: error)
        }

        viewState.isLoading = false
    }

    private func apply(content: CommunityDetailContent) {
        detail = content.detail
        distanceMeters = content.distanceMeters
        applyViewState(detail: content.detail, distanceMeters: content.distanceMeters)
        viewState.errorMessage = nil
        viewState.hasLoadedContent = true
        viewState.emptyState = nil
    }

    private func applyViewState(detail: CommunityPostDetail, distanceMeters: Double?) {
        viewState.heroEyebrow = detail.summary.category ?? "커뮤니티"
        viewState.heroTitle = detail.summary.title
        viewState.heroMessage = makeHeroMessage(from: detail)
        viewState.postCard = makePostCardModel(
            from: detail.summary,
            distanceMeters: distanceMeters
        )
        viewState.footerTitle = makeFooterTitle(from: detail)
        viewState.footerMessage = makeFooterMessage(from: detail)
    }

    private func toggleLikeStatus() async {
        guard let currentDetail = detail else { return }

        let currentSummary = currentDetail.summary
        let optimisticLikeStatus = !currentSummary.isLiked
        let previousDetail = currentDetail

        let optimisticDetail = CommunityPostDetail(
            summary: makeUpdatedSummary(
                from: currentSummary,
                isLiked: optimisticLikeStatus
            ),
            comments: currentDetail.comments
        )

        detail = optimisticDetail
        applyViewState(detail: optimisticDetail, distanceMeters: distanceMeters)

        do {
            let confirmedStatus = try await interactor.updateLikeStatus(isLiked: optimisticLikeStatus)
            let confirmedDetail = CommunityPostDetail(
                summary: makeUpdatedSummary(
                    from: currentSummary,
                    isLiked: confirmedStatus
                ),
                comments: currentDetail.comments
            )
            detail = confirmedDetail
            applyViewState(detail: confirmedDetail, distanceMeters: distanceMeters)
        } catch {
            detail = previousDetail
            applyViewState(detail: previousDetail, distanceMeters: distanceMeters)
            viewState.errorMessage = resolveErrorMessage(from: error)
        }
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

    private func makePostCardModel(
        from summary: CommunityPostSummary,
        distanceMeters: Double?
    ) -> CommunityCard.Model {
        CommunityCard.Model(
            id: summary.id,
            authorName: summary.creator.nick,
            authorAvatarPath: summary.creator.profileImagePath,
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

    private func makeHeroMessage(from detail: CommunityPostDetail) -> String {
        let timeText = makeRelativeTimeText(from: detail.summary.createdAt)
        let commentText = detail.totalCommentCount == 0 ? "아직 댓글 없음" : "댓글 \(detail.totalCommentCount)개"
        return "\(detail.summary.creator.nick) · \(timeText) · \(commentText)"
    }

    private func makeFooterTitle(from detail: CommunityPostDetail) -> String {
        if detail.comments.isEmpty {
            return "첫 댓글을 기다리고 있어요"
        }

        return "댓글 미리보기"
    }

    private func makeFooterMessage(from detail: CommunityPostDetail) -> String {
        guard let firstComment = detail.comments.first else {
            return "아직 등록된 댓글이 없어요. 다음 턴에서 댓글 작성과 pagination을 이 화면 위에 확장하면 됩니다."
        }

        let replySuffix = firstComment.replies.isEmpty ? "" : " · 답글 \(firstComment.replies.count)개"
        return "\(firstComment.creator.nick): \(firstComment.content)\(replySuffix)"
    }

    private func makeDistanceText(from distanceMeters: Double?) -> String {
        guard let distanceMeters else {
            return "-"
        }

        return distanceFormatter.string(fromMeters: distanceMeters).uppercased()
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
}
