import CoreLocation
import Foundation

@MainActor
final class CommunityPresenter: ObservableObject {
    @Published private(set) var viewState: CommunityViewState

    private let interactor: CommunityInteracting
    private let router: CommunityRouting
    private let sessionStore: SessionStore
    private let routesSearchSubmissions: Bool
    private let distanceFormatter = DistanceFormatter()
    private let relativeDateFormatter = RelativeDateTimeFormatter()

    private var hasLoaded = false
    private var allPosts: [CommunityPostSummary] = []
    private var activeQuery: String?
    private var referenceLocation: CommunityReferenceLocation?
    private var isPaging = false
    private var recentlySubmittedPostID: String?

    init(
        interactor: CommunityInteracting,
        router: CommunityRouting,
        sessionStore: SessionStore,
        initialQuery: String? = nil,
        routesSearchSubmissions: Bool = true
    ) {
        self.interactor = interactor
        self.router = router
        self.sessionStore = sessionStore
        self.routesSearchSubmissions = routesSearchSubmissions
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
            if routesSearchSubmissions, let query {
                router.routeToSearch(query: query)
                return
            }
            activeQuery = query
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
        case .sortSelected(let sortID):
            guard let selectedSort = viewState.sortOptions.first(where: { $0.id == sortID }) else { return }
            viewState.selectedSort = selectedSort
            viewState.nextCursor = nil
            await loadFeed(isRefresh: false)
        case .distanceSelected(let distanceID):
            guard let selectedDistance = viewState.distanceOptions.first(where: { $0.id == distanceID }) else { return }
            viewState.selectedDistance = selectedDistance
            viewState.nextCursor = nil
            await loadFeed(isRefresh: false)
        case .filterChipTapped(let chipID):
            guard viewState.filterChips.contains(where: { $0.id == chipID }) else { return }
            if viewState.selectedFilterChipIDs.contains(chipID) {
                viewState.selectedFilterChipIDs.remove(chipID)
            } else {
                viewState.selectedFilterChipIDs.insert(chipID)
            }
            viewState.nextCursor = nil
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
        }
    }

    private func loadFeed(isRefresh: Bool, reason: String? = nil) async {
        if isRefresh || hasLoaded {
            viewState.isRefreshing = true
        } else {
            viewState.isLoading = true
        }
        viewState.feedStatus = .loading
        viewState.errorMessage = nil
        viewState.emptyState = nil

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
            apply(content: content)
            hasLoaded = true
        } catch {
            viewState.errorMessage = resolveErrorMessage(from: error)
            if allPosts.isEmpty {
                viewState.featuredBanner = nil
                viewState.emptyState = makeFailureEmptyState(for: error)
                viewState.feedStatus = feedStatus(for: error)
            } else {
                viewState.feedStatus = .content
            }
        }

        viewState.isLoading = false
        viewState.isRefreshing = false
    }

    private func apply(content: CommunityFeedContent) {
        viewState.featuredBanner = content.featuredBanner
        referenceLocation = content.referenceLocation
        allPosts = content.posts
        viewState.nextCursor = content.nextCursor
        applyFilters()
    }

    private func applyFilters() {
        var filteredPosts = allPosts

        if let maxDistance = viewState.selectedDistance.meters,
           referenceLocation != nil {
            filteredPosts = filteredPosts.filter { post in
                guard let distance = distance(from: post) else {
                    return true
                }
                return distance <= maxDistance
            }
        }

        for selectedFilterID in viewState.selectedFilterChipIDs {
            filteredPosts = filteredPosts.filter { post in
                switch selectedFilterID {
                case "nearby":
                    guard let distance = distance(from: post) else {
                        return false
                    }
                    return distance <= 500
                case "video":
                    return post.mediaPaths.contains(where: {
                        MediaTypeResolver.resolve(from: $0) == .video
                    })
                case "store":
                    return post.store != nil
                default:
                    return true
                }
            }
        }

        switch viewState.selectedSort.id {
        case CommunitySortOption.popular.id:
            filteredPosts.sort { lhs, rhs in
                if lhs.likeCount == rhs.likeCount {
                    return (distance(from: lhs) ?? .greatestFiniteMagnitude) < (distance(from: rhs) ?? .greatestFiniteMagnitude)
                }
                return lhs.likeCount > rhs.likeCount
            }
        case CommunitySortOption.nearest.id:
            filteredPosts.sort { lhs, rhs in
                let lhsDistance = distance(from: lhs) ?? .greatestFiniteMagnitude
                let rhsDistance = distance(from: rhs) ?? .greatestFiniteMagnitude
                if lhsDistance == rhsDistance {
                    return lhs.likeCount > rhs.likeCount
                }
                return lhsDistance < rhsDistance
            }
        default:
            filteredPosts.sort { lhs, rhs in
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
            break
        }

        viewState.posts = filteredPosts.map(makeCommunityCardModel)
        viewState.emptyState = makeEmptyState(filteredPosts: filteredPosts)
        viewState.feedStatus = filteredPosts.isEmpty ? .empty : .content
    }

    private func handleSubmittedPost(postID: String) async {
        recentlySubmittedPostID = postID
        activeQuery = nil
        viewState.searchText = ""
        viewState.selectedFilterChipIDs.removeAll()
        viewState.selectedSort = .latest
        viewState.nextCursor = nil

        await loadFeed(isRefresh: true, reason: "postCreated")

        guard allPosts.contains(where: { $0.id == postID }) == false else {
            return
        }

        await mergeSubmittedPost(postID: postID)
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

            viewState.selectedFilterChipIDs.removeAll()

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
            allPosts.append(contentsOf: content.posts)
            viewState.nextCursor = content.nextCursor
            applyFilters()
        } catch {
            viewState.errorMessage = resolveErrorMessage(from: error)
            if viewState.posts.isEmpty {
                viewState.emptyState = makeFailureEmptyState(for: error)
            }
        }
    }

    private func toggleLike(for postID: String) async {
        guard let index = allPosts.firstIndex(where: { $0.id == postID }) else {
            return
        }

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
        } catch {
            allPosts = previousPosts
            applyFilters()
            viewState.errorMessage = resolveErrorMessage(from: error)
        }
    }

    private func makeCommunityCardModel(from post: CommunityPostSummary) -> CommunityCard.Model {
        CommunityCard.Model(
            id: post.id,
            authorName: post.creator.nick,
            authorAvatarPath: post.creator.profileImagePath,
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
        guard let referenceLocation,
              let longitude = post.longitude,
              let latitude = post.latitude else {
            return nil
        }

        let userLocation = CLLocation(latitude: referenceLocation.latitude, longitude: referenceLocation.longitude)
        let postLocation = CLLocation(latitude: latitude, longitude: longitude)
        return userLocation.distance(from: postLocation)
    }

    private func makeDistanceText(from post: CommunityPostSummary) -> String {
        guard let distance = distance(from: post) else {
            return "-"
        }

        return distanceFormatter.string(fromMeters: distance).uppercased()
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
                return CommunityEmptyState(
                    title: "위치가 필요해요",
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
        case .unavailable:
            return .failure
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
}
