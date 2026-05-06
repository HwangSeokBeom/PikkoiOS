import CoreLocation
import Foundation

@MainActor
final class CommunityPresenter: ObservableObject {
    @Published private(set) var viewState: CommunityViewState

    private let interactor: CommunityInteracting
    private let router: CommunityRouting
    private let sessionStore: SessionStore
    private let notificationService: AppNotificationService
    private let communityNotificationSnapshotStore: CommunityNotificationSnapshotStore
    private let distanceFormatter = DistanceFormatter()
    private let distanceCalculator = CommunityDistanceCalculator()
    private let relativeDateFormatter = RelativeDateTimeFormatter()

    private var hasLoaded = false
    private var allPosts: [CommunityPostSummary] = []
    private var activeQuery: String?
    private var referenceLocation: CommunityReferenceLocation?
    private var isPaging = false
    private var recentlySubmittedPostID: String?
    private var feedRequestID = 0
    private var updatingLikePostIDs: Set<String> = []

    init(
        interactor: CommunityInteracting,
        router: CommunityRouting,
        sessionStore: SessionStore,
        notificationService: AppNotificationService = NoopAppNotificationService(),
        communityNotificationSnapshotStore: CommunityNotificationSnapshotStore = InMemoryCommunityNotificationSnapshotStore(),
        initialQuery: String? = nil,
        routesSearchSubmissions: Bool = true
    ) {
        self.interactor = interactor
        self.router = router
        self.sessionStore = sessionStore
        self.notificationService = notificationService
        self.communityNotificationSnapshotStore = communityNotificationSnapshotStore
        _ = routesSearchSubmissions
        let trimmedInitialQuery = initialQuery?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.activeQuery = {
            guard let trimmedInitialQuery, !trimmedInitialQuery.isEmpty else {
                return nil
            }
            return trimmedInitialQuery
        }()
        self.viewState = CommunityViewState(searchText: initialQuery ?? "")
        self.relativeDateFormatter.locale = Locale(identifier: "ko_KR")
        self.relativeDateFormatter.unitsStyle = .full
    }

    func send(_ action: CommunityAction) async {
        switch action {
        case .onAppear:
            guard !hasLoaded else { return }
            await loadFeed(isRefresh: false)
        case .refreshRequested:
            await loadFeed(isRefresh: true)
        case .loginRequiredTapped:
            router.routeToAuth(context: .communityCompose, routeAfterAuth: nil)
        case .searchTextChanged(let text):
            viewState.searchText = text
        case .searchSubmitted:
            let query = normalizedQuery(viewState.searchText)
            activeQuery = query
            viewState.searchText = query ?? ""
            viewState.nextCursor = nil
            #if DEBUG
            Logger.shared.debug("[CommunitySearch] query=\"\(query ?? "")\"")
            #endif
            await loadFeed(isRefresh: false)
        case .searchCleared:
            activeQuery = nil
            viewState.searchText = ""
            viewState.nextCursor = nil
            #if DEBUG
            Logger.shared.debug("[CommunitySearch] query=\"\"")
            #endif
            await loadFeed(isRefresh: false)
        case .composeTapped:
            guard sessionStore.isAuthenticated else {
                router.routeToAuth(
                    context: .communityCompose,
                    routeAfterAuth: .communityComposer(mode: .create, initialDraft: nil)
                )
                return
            }
            router.routeToComposer()
        case .sortSelected(let categoryID):
            guard let category = CommunitySortCategory(rawValue: categoryID) else { return }
            await selectSort(category.defaultSelection)
        case .sortToggleTapped:
            await selectSort(viewState.selectedSort.toggledDirection)
        case .distanceSelected(let distanceID):
            guard let selectedDistance = viewState.distanceOptions.first(where: { $0.id == distanceID }) else { return }
            guard viewState.selectedDistance != selectedDistance else { return }
            viewState.selectedDistance = selectedDistance
            viewState.nextCursor = nil
            await loadFeed(isRefresh: false)
        case .filterChipTapped(let chipID):
            guard let filter = CommunityFilter(rawValue: chipID) else { return }
            if viewState.selectedFilters.contains(filter) {
                viewState.selectedFilters.remove(filter)
            } else {
                viewState.selectedFilters.insert(filter)
            }
            viewState.nextCursor = nil
            applyFilters()
            await loadFeed(isRefresh: false)
        case .postSubmitted(let postID):
            await handleSubmittedPost(postID: postID)
        case .postTapped(let postID):
            router.routeToPostDetail(postID: postID)
        case .storeSnippetTapped(let storeID):
            router.routeToStoreDetail(storeID: storeID)
        case .postAppeared(let postID):
            await loadNextPageIfNeeded(triggeredBy: postID)
        case .likeTapped(let postID):
            await toggleLike(for: postID)
        case .postChangeReceived(let event):
            applyPostChange(event)
        }
    }

    private func loadFeed(isRefresh: Bool, reason: String? = nil) async {
        feedRequestID += 1
        let requestID = feedRequestID

        if isRefresh || hasLoaded {
            viewState.isRefreshing = true
        } else {
            viewState.isLoading = true
        }
        viewState.feedStatus = .loading
        viewState.errorMessage = nil
        viewState.emptyState = nil
        defer {
            if requestID == feedRequestID {
                viewState.isLoading = false
                viewState.isRefreshing = false
            }
        }

        #if DEBUG
        Logger.shared.debug(
            "[CommunityFilter] selected distance=\(viewState.selectedDistance.title) direction=\(viewState.selectedSort.direction.rawValue) orderBy=\(viewState.selectedSort.requestOrderBy.rawValue)"
        )
        Logger.shared.debug(
            "[CommunityList] \(isRefresh ? "refresh started" : "reload") requestID=\(requestID) category=\(viewState.selectedSort.category.id) direction=\(viewState.selectedSort.direction.rawValue) distance=\(viewState.selectedDistance.title) hasLocation=\(viewState.hasReferenceLocation) cursor=\(viewState.nextCursor ?? "nil")"
        )
        #endif

        if reason == "postCreated" {
            viewState.nextCursor = nil
            #if DEBUG
            Logger.shared.debug("[CommunityList] reload reason=postCreated")
            #endif
        }

        do {
            let content = try await interactor.loadFeed(
                query: activeQuery,
                selectedDistance: viewState.selectedDistance,
                selectedSort: viewState.selectedSort
            )
            guard requestID == feedRequestID else {
                #if DEBUG
                Logger.shared.debug("[CommunityList] stale response ignored requestID=\(requestID)")
                #endif
                return
            }
            apply(content: content)
            hasLoaded = true
        } catch is CancellationError {
            guard requestID == feedRequestID else {
                #if DEBUG
                Logger.shared.debug("[CommunityList] stale response ignored requestID=\(requestID)")
                #endif
                return
            }
            #if DEBUG
            Logger.shared.debug("[CommunityList] request cancelled, suppress user error")
            #endif
        } catch {
            guard requestID == feedRequestID else {
                #if DEBUG
                Logger.shared.debug("[CommunityList] stale response ignored requestID=\(requestID)")
                #endif
                return
            }
            viewState.errorMessage = transientErrorMessage(from: error)
            if let feedError = error as? CommunityFeedError,
               case .locationRequired = feedError {
                referenceLocation = nil
                viewState.hasReferenceLocation = false
            }
            if allPosts.isEmpty {
                viewState.featuredBanner = nil
                viewState.emptyState = makeFailureEmptyState(for: error)
                viewState.feedStatus = feedStatus(for: error)
            } else {
                viewState.feedStatus = .content
            }
        }
    }

    private func apply(content: CommunityFeedContent) {
        viewState.featuredBanner = content.featuredBanner
        referenceLocation = content.referenceLocation
        viewState.hasReferenceLocation = content.referenceLocation != nil
        allPosts = content.posts
        detectCommunityListReactions(in: content.posts)
        viewState.nextCursor = content.nextCursor
        applyFilters()
    }

    private func detectCommunityListReactions(in posts: [CommunityPostSummary]) {
        for post in posts {
            let currentSnapshot = CommunityPostNotificationSnapshot(
                postId: post.id,
                commentCount: nil,
                likeCount: post.likeCount,
                updatedAt: post.updatedAt ?? post.createdAt ?? Date()
            )
            defer {
                communityNotificationSnapshotStore.saveSnapshot(currentSnapshot)
            }

            guard post.creator.id == sessionStore.currentUserID,
                  let previousSnapshot = communityNotificationSnapshotStore.snapshot(for: post.id) else {
                continue
            }

            if let previousLikeCount = previousSnapshot.likeCount,
               post.likeCount > previousLikeCount {
                notificationService.handleCommunityLike(
                    postId: post.id,
                    commentId: nil,
                    actorUserId: nil,
                    actorName: nil
                )
            }
        }
    }

    private func applyFilters() {
        var filteredPosts = allPosts

        if let maxDistance = viewState.selectedDistance.meters {
            if referenceLocation != nil {
                filteredPosts = filteredPosts.filter { post in
                    guard let distance = distance(from: post) else {
                        return false
                    }
                    return distance <= maxDistance
                }
                #if DEBUG
                Logger.shared.debug("[CommunityList] distanceFilter=\(Int(maxDistance))m resultCount=\(filteredPosts.count)")
                #endif
            } else {
                #if DEBUG
                Logger.shared.info("[CommunityLocation] latExists=false lonExists=false permission=unavailable")
                #endif
            }
        }

        for selectedFilter in viewState.selectedFilters {
            filteredPosts = filteredPosts.filter { post in
                switch selectedFilter {
                case .nearbyOnly:
                    guard referenceLocation != nil else {
                        return true
                    }
                    guard let distance = distance(from: post) else {
                        return false
                    }
                    return distance <= 500
                case .videoOnly:
                    return post.mediaPaths.contains(where: {
                        MediaTypeResolver.resolve(from: $0) == .video
                    })
                case .storeTag:
                    return post.store != nil
                }
            }
        }

        sort(&filteredPosts, by: viewState.selectedSort)

        viewState.posts = filteredPosts.map(makeCommunityCardModel)
        viewState.emptyState = makeEmptyState(filteredPosts: filteredPosts)
        viewState.feedStatus = filteredPosts.isEmpty ? .empty : .content
        viewState.errorMessage = nil
        #if DEBUG
        Logger.shared.debug(
            "[CommunityList] response count=\(allPosts.count) filtered=\(filteredPosts.count) state=\(viewState.feedStatus.debugName) clearError=true"
        )
        #endif
    }

    private func handleSubmittedPost(postID: String) async {
        recentlySubmittedPostID = postID
        activeQuery = nil
        viewState.searchText = ""
        viewState.selectedFilters.removeAll()
        viewState.selectedSort = .latest
        viewState.nextCursor = nil

        await loadFeed(isRefresh: true, reason: "postCreated")

        guard allPosts.contains(where: { $0.id == postID }) == false else {
            return
        }

        await mergeSubmittedPost(postID: postID)
    }

    private func selectSort(_ selectedSort: CommunitySort) async {
        guard viewState.selectedSort != selectedSort else { return }
        viewState.selectedSort = selectedSort
        viewState.nextCursor = nil
        #if DEBUG
        Logger.shared.debug(
            "[CommunityFilter] selected distance=\(viewState.selectedDistance.title) direction=\(selectedSort.direction.rawValue) orderBy=\(selectedSort.requestOrderBy.rawValue)"
        )
        #endif
        await loadFeed(isRefresh: false)
    }

    func shouldRefreshAfterDetailDismiss(postID: String?) -> Bool {
        guard let postID, postID == recentlySubmittedPostID else {
            return true
        }

        recentlySubmittedPostID = nil
        return false
    }

    private func mergeSubmittedPost(postID: String) async {
        viewState.errorMessage = nil
        viewState.emptyState = nil

        do {
            let createdPost = try await interactor.loadPost(postID: postID)
            allPosts.removeAll { $0.id == createdPost.id }
            allPosts.insert(createdPost, at: 0)
            viewState.nextCursor = nil
            hasLoaded = true

            if activeQuery != nil {
                activeQuery = nil
                viewState.searchText = ""
            }

            viewState.selectedFilters.removeAll()

            applyFilters()
            #if DEBUG
            Logger.shared.debug("[CommunityList] inserted created post postID=\(createdPost.id)")
            #endif
        } catch {
            viewState.errorMessage = resolveErrorMessage(from: error)
            if allPosts.isEmpty {
                viewState.featuredBanner = nil
                viewState.emptyState = makeFailureEmptyState(for: error)
                viewState.feedStatus = feedStatus(for: error)
            }
        }
    }

    private func loadNextPageIfNeeded(triggeredBy postID: String) async {
        guard activeQuery == nil,
              !isPaging,
              let nextCursor = viewState.nextCursor,
              postID == viewState.posts.last?.id else {
            return
        }

        isPaging = true
        defer { isPaging = false }

        do {
            let content = try await interactor.loadMorePosts(
                selectedDistance: viewState.selectedDistance,
                selectedSort: viewState.selectedSort,
                nextCursor: nextCursor
            )
            referenceLocation = content.referenceLocation ?? referenceLocation
            viewState.hasReferenceLocation = referenceLocation != nil
            allPosts.append(contentsOf: content.posts)
            viewState.nextCursor = content.nextCursor
            applyFilters()
        } catch {
            viewState.errorMessage = transientErrorMessage(from: error)
            if viewState.posts.isEmpty {
                viewState.emptyState = makeFailureEmptyState(for: error)
            }
        }
    }

    private func toggleLike(for postID: String) async {
        guard !updatingLikePostIDs.contains(postID) else {
            return
        }
        guard let index = allPosts.firstIndex(where: { $0.id == postID }) else {
            return
        }

        updatingLikePostIDs.insert(postID)
        defer { updatingLikePostIDs.remove(postID) }

        let currentPost = allPosts[index]
        let updatedLikeStatus = !currentPost.isLiked
        let likeDelta = updatedLikeStatus ? 1 : -1

        let previousPosts = allPosts

        allPosts[index] = CommunityPostSummary(
            id: currentPost.id,
            category: currentPost.category,
            title: currentPost.title,
            content: currentPost.content,
            creator: currentPost.creator,
            mediaPaths: currentPost.mediaPaths,
            store: currentPost.store,
            isLiked: updatedLikeStatus,
            likeCount: max(currentPost.likeCount + likeDelta, 0),
            longitude: currentPost.longitude,
            latitude: currentPost.latitude,
            createdAt: currentPost.createdAt,
            updatedAt: currentPost.updatedAt
        )

        applyFilters()

        do {
            let confirmedLikeStatus = try await interactor.updateLikeStatus(postID: postID, isLiked: updatedLikeStatus)
            guard let confirmedIndex = allPosts.firstIndex(where: { $0.id == postID }) else {
                return
            }

            let optimisticPost = allPosts[confirmedIndex]
            let countAdjustment: Int
            switch (optimisticPost.isLiked, confirmedLikeStatus) {
            case (true, false):
                countAdjustment = -1
            case (false, true):
                countAdjustment = 1
            default:
                countAdjustment = 0
            }

            allPosts[confirmedIndex] = CommunityPostSummary(
                id: optimisticPost.id,
                category: optimisticPost.category,
                title: optimisticPost.title,
                content: optimisticPost.content,
                creator: optimisticPost.creator,
                mediaPaths: optimisticPost.mediaPaths,
                store: optimisticPost.store,
                isLiked: confirmedLikeStatus,
                likeCount: max(optimisticPost.likeCount + countAdjustment, 0),
                longitude: optimisticPost.longitude,
                latitude: optimisticPost.latitude,
                createdAt: optimisticPost.createdAt,
                updatedAt: optimisticPost.updatedAt
            )
            applyFilters()
            postCommunityChange(for: allPosts[confirmedIndex])
        } catch {
            allPosts = previousPosts
            applyFilters()
            viewState.errorMessage = transientErrorMessage(from: error)
        }
    }

    private func applyPostChange(_ event: CommunityPostChangeNotification) {
        guard let index = allPosts.firstIndex(where: { $0.id == event.postID }) else {
            return
        }

        let currentPost = allPosts[index]
        allPosts[index] = CommunityPostSummary(
            id: currentPost.id,
            category: currentPost.category,
            title: currentPost.title,
            content: currentPost.content,
            creator: currentPost.creator,
            mediaPaths: currentPost.mediaPaths,
            store: currentPost.store,
            isLiked: event.isLiked ?? currentPost.isLiked,
            likeCount: event.likeCount ?? currentPost.likeCount,
            longitude: currentPost.longitude,
            latitude: currentPost.latitude,
            createdAt: currentPost.createdAt,
            updatedAt: currentPost.updatedAt
        )
        applyFilters()
    }

    private func postCommunityChange(for post: CommunityPostSummary) {
        let event = CommunityPostChangeNotification(
            postID: post.id,
            isLiked: post.isLiked,
            likeCount: post.likeCount,
            commentCount: nil
        )
        NotificationCenter.default.post(
            name: .pikkoCommunityPostDidChange,
            object: nil,
            userInfo: [CommunityPostChangeNotificationUserInfoKey.event: event]
        )
    }

    private func makeCommunityCardModel(from post: CommunityPostSummary) -> CommunityCard.Model {
        CommunityCard.Model(
            id: post.id,
            authorID: post.creator.id,
            authorName: post.creator.nick,
            authorAvatarPath: post.creator.profileImagePath,
            canChatWithAuthor: false,
            timeText: makeRelativeTimeText(from: post.createdAt),
            title: post.title,
            bodyText: post.content,
            likeText: "\(post.likeCount)개",
            distanceText: makeDistanceText(from: post),
            media: post.mediaPaths.enumerated().map { index, path in
                .init(id: "\(post.id)-media-\(index)", path: path)
            },
            storeSnippet: post.store.map {
                .init(
                    id: $0.id,
                    title: $0.name,
                    subtitle: storeSubtitle(from: $0),
                    imagePath: $0.imagePaths.first
                )
            },
            isLiked: post.isLiked
        )
    }

    private func distance(from post: CommunityPostSummary) -> Double? {
        let distance = distanceCalculator.distanceMeters(
            from: referenceLocation,
            toLongitude: post.longitude,
            latitude: post.latitude
        )
        #if DEBUG
        Logger.shared.debug(
            "[CommunityDistance] postID=\(post.id) hasGeo=\(post.longitude != nil && post.latitude != nil) distance=\(distance.map { String(Int($0.rounded())) } ?? "nil")"
        )
        #endif
        return distance
    }

    private func makeDistanceText(from post: CommunityPostSummary) -> String {
        guard let distance = distance(from: post) else {
            return "-"
        }

        return distanceFormatter.string(fromMeters: distance)
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

    private func storeSubtitle(from store: CommunityPostStoreSummary) -> String {
        let categoryText = store.category ?? "가게"

        if let closeTime = store.closeTime, !closeTime.isEmpty {
            return "\(categoryText) · 마감 \(closeTime)"
        }

        return categoryText
    }

    private func normalizedQuery(_ query: String) -> String? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func makeEmptyState(filteredPosts: [CommunityPostSummary]) -> CommunityEmptyState? {
        guard filteredPosts.isEmpty else {
            return nil
        }

        if allPosts.isEmpty {
            if activeQuery != nil {
                return CommunityEmptyState(
                    title: "검색 결과가 없어요",
                    message: "다른 키워드로 다시 검색해 보세요.",
                    actionTitle: "다시 불러오기"
                )
            }

            return CommunityEmptyState(
                title: "표시할 게시글이 없어요",
                message: "조금 뒤 다시 확인하거나 검색 조건을 바꿔 보세요.",
                actionTitle: "다시 불러오기"
            )
        }

        if viewState.selectedDistance.meters != nil, referenceLocation != nil {
            return CommunityEmptyState(
                title: "주변 게시글이 없어요",
                message: "\(viewState.selectedDistance.title) 안에서 볼 수 있는 게시글이 아직 없어요.",
                actionTitle: "다시 불러오기"
            )
        }

        return CommunityEmptyState(
            title: "조건에 맞는 게시글이 없어요",
            message: "거리, 정렬, 필터를 바꿔서 다시 확인해 주세요.",
            actionTitle: "다시 불러오기"
        )
    }

    private func makeFailureEmptyState(for error: Error) -> CommunityEmptyState {
        if let communityError = error as? CommunityFeedError {
            switch communityError {
            case .authenticationRequired:
                return CommunityEmptyState(
                    title: "로그인이 필요해요",
                    message: "커뮤니티 피드는 로그인 후 볼 수 있어요. 인증 후 다시 시도해 주세요.",
                    actionTitle: "로그인하러 가기",
                    requiresAuthentication: true
                )
            case .locationRequired(let message):
                #if DEBUG
                Logger.shared.debug("[CommunityLocation] missing location, show locationRequired")
                #endif
                return CommunityEmptyState(
                    title: "위치가 필요해요",
                    message: message,
                    actionTitle: "다시 시도"
                )
            case .networkUnavailable(let message):
                return CommunityEmptyState(
                    title: "커뮤니티를 불러오지 못했어요",
                    message: message,
                    actionTitle: "다시 시도"
                )
            case .unavailable(let message):
                return CommunityEmptyState(
                    title: "커뮤니티를 불러오지 못했어요",
                    message: message,
                    actionTitle: "다시 시도"
                )
            }
        }

        return CommunityEmptyState(
            title: "커뮤니티를 불러오지 못했어요",
            message: resolveErrorMessage(from: error),
            actionTitle: "다시 시도"
        )
    }

    private func feedStatus(for error: Error) -> CommunityFeedStatus {
        guard let communityError = error as? CommunityFeedError else {
            return .failure
        }

        switch communityError {
        case .authenticationRequired:
            return .authenticationRequired
        case .locationRequired:
            return .locationRequired
        case .networkUnavailable:
            return .failure
        case .unavailable:
            return .failure
        }
    }

    private func transientErrorMessage(from error: Error) -> String? {
        guard shouldShowTransientError(for: error) else {
            return nil
        }

        return resolveErrorMessage(from: error)
    }

    private func shouldShowTransientError(for error: Error) -> Bool {
        guard let communityError = error as? CommunityFeedError else {
            return false
        }

        switch communityError {
        case .networkUnavailable:
            return true
        case .authenticationRequired, .locationRequired, .unavailable:
            return false
        }
    }

    private func resolveErrorMessage(from error: Error) -> String {
        if let localizedError = error as? LocalizedError,
           let description = localizedError.errorDescription,
           !description.isEmpty {
            return description
        }

        return error.localizedDescription
    }

    private func sort(_ posts: inout [CommunityPostSummary], by selection: CommunitySort) {
        switch (selection.category, selection.direction) {
        case (.latest, .descending):
            posts.sort(by: compareCreatedAtDescending)
        case (.latest, .ascending):
            posts.sort(by: compareCreatedAtAscending)
        case (.popularity, .descending):
            posts.sort { lhs, rhs in
                // Swagger exposes `likes` as the popularity order. The summary
                // entity currently exposes likeCount only, so "없는순" uses the
                // same field ascending as a client-side fallback.
                if lhs.likeCount == rhs.likeCount {
                    return compareCreatedAtDescending(lhs, rhs)
                }
                return lhs.likeCount > rhs.likeCount
            }
        case (.popularity, .ascending):
            posts.sort { lhs, rhs in
                if lhs.likeCount == rhs.likeCount {
                    return compareCreatedAtDescending(lhs, rhs)
                }
                return lhs.likeCount < rhs.likeCount
            }
        case (.distance, .ascending):
            posts.sort(by: compareDistanceAscending)
        case (.distance, .descending):
            posts.sort(by: compareDistanceDescending)
        }
    }

    private func compareCreatedAtDescending(
        _ lhs: CommunityPostSummary,
        _ rhs: CommunityPostSummary
    ) -> Bool {
        switch (lhs.createdAt, rhs.createdAt) {
        case let (lhsDate?, rhsDate?):
            return lhsDate > rhsDate
        case (.some, .none):
            return true
        case (.none, .some):
            return false
        case (.none, .none):
            return lhs.title < rhs.title
        }
    }

    private func compareCreatedAtAscending(
        _ lhs: CommunityPostSummary,
        _ rhs: CommunityPostSummary
    ) -> Bool {
        switch (lhs.createdAt, rhs.createdAt) {
        case let (lhsDate?, rhsDate?):
            return lhsDate < rhsDate
        case (.some, .none):
            return true
        case (.none, .some):
            return false
        case (.none, .none):
            return lhs.title < rhs.title
        }
    }

    private func compareDistanceAscending(
        _ lhs: CommunityPostSummary,
        _ rhs: CommunityPostSummary
    ) -> Bool {
        switch (distance(from: lhs), distance(from: rhs)) {
        case let (lhsDistance?, rhsDistance?):
            if lhsDistance == rhsDistance {
                return compareCreatedAtDescending(lhs, rhs)
            }
            return lhsDistance < rhsDistance
        case (.some, .none):
            return true
        case (.none, .some):
            return false
        case (.none, .none):
            return compareCreatedAtDescending(lhs, rhs)
        }
    }

    private func compareDistanceDescending(
        _ lhs: CommunityPostSummary,
        _ rhs: CommunityPostSummary
    ) -> Bool {
        switch (distance(from: lhs), distance(from: rhs)) {
        case let (lhsDistance?, rhsDistance?):
            if lhsDistance == rhsDistance {
                return compareCreatedAtDescending(lhs, rhs)
            }
            return lhsDistance > rhsDistance
        case (.some, .none):
            return true
        case (.none, .some):
            return false
        case (.none, .none):
            return compareCreatedAtDescending(lhs, rhs)
        }
    }

}

private extension CommunityFeedStatus {
    var debugName: String {
        switch self {
        case .loading:
            return "loading"
        case .content:
            return "loaded"
        case .empty:
            return "emptyNoPosts"
        case .failure:
            return "error"
        case .locationRequired:
            return "locationRequired"
        case .authenticationRequired:
            return "authenticationRequired"
        }
    }
}
