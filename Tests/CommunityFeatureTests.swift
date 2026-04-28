import XCTest
@testable import Pikko

@MainActor
final class CommunityFeatureTests: XCTestCase {
    func testGuestComposeTapRoutesToAuth() async {
        let router = CommunityRouter()
        let presenter = CommunityPresenter(
            interactor: StubCommunityInteractor(),
            router: router,
            sessionStore: makeSessionStore()
        )

        await presenter.send(.composeTapped)

        XCTAssertTrue(router.isAuthPresented)
        XCTAssertNil(router.pendingRoute)
        XCTAssertEqual(router.authPresentationContext, .communityCompose)
    }

    func testAuthenticatedComposeTapRoutesToComposer() async {
        let sessionStore = makeSessionStore()
        sessionStore.apply(
            session: UserSession(
                userID: "user-1",
                email: "user-1@example.com",
                displayName: "테스트 사용자",
                profileImagePath: nil,
                accessToken: "access-token",
                refreshToken: "refresh-token"
            )
        )
        let router = CommunityRouter()
        let presenter = CommunityPresenter(
            interactor: StubCommunityInteractor(),
            router: router,
            sessionStore: sessionStore
        )

        await presenter.send(.composeTapped)

        XCTAssertEqual(router.pendingRoute, .communityComposer(mode: .create, initialDraft: nil))
        XCTAssertFalse(router.isAuthPresented)
    }

    func testAuthCompletionRoutesGuestComposeToComposer() async {
        let router = CommunityRouter()
        let presenter = CommunityPresenter(
            interactor: StubCommunityInteractor(),
            router: router,
            sessionStore: makeSessionStore()
        )

        await presenter.send(.composeTapped)
        router.completeAuthentication()
        await Task.yield()

        XCTAssertEqual(router.pendingRoute, .communityComposer(mode: .create, initialDraft: nil))
    }

    func testPostSubmittedInsertsCreatedPostWhenReloadIsStillEmpty() async {
        let presenter = CommunityPresenter(
            interactor: StubCommunityInteractor(),
            router: CommunityRouter(),
            sessionStore: makeSessionStore()
        )

        await presenter.send(.postSubmitted("created-post"))

        XCTAssertEqual(presenter.viewState.feedStatus, .content)
        XCTAssertEqual(presenter.viewState.posts.first?.id, "created-post")
        XCTAssertNil(presenter.viewState.nextCursor)
        XCTAssertEqual(presenter.viewState.searchText, "")
    }

    func testCommunitySortMapsToSwaggerOrderByValues() {
        XCTAssertEqual(CommunitySort.latest.title, "최신순")
        XCTAssertEqual(CommunitySort.latest.category, .latest)
        XCTAssertEqual(CommunitySort.latest.direction, .descending)
        XCTAssertEqual(CommunitySort.latest.requestOrderBy, .createdAt)

        XCTAssertEqual(CommunitySort.popular.title, "인기순")
        XCTAssertEqual(CommunitySort.popular.category, .popularity)
        XCTAssertEqual(CommunitySort.popular.direction, .descending)
        XCTAssertEqual(CommunitySort.popular.requestOrderBy, .likes)

        XCTAssertEqual(CommunitySort.distance.title, "가까운순")
        XCTAssertEqual(CommunitySort.distance.category, .distance)
        XCTAssertEqual(CommunitySort.distance.direction, .ascending)
        XCTAssertEqual(CommunitySort.distance.requestOrderBy, .createdAt)
    }

    func testSortToggleFlipsDirectionAndReloadsFirstPage() async {
        let interactor = RecordingCommunityInteractor(nextCursors: ["cursor-2", nil, nil])
        let presenter = CommunityPresenter(
            interactor: interactor,
            router: CommunityRouter(),
            sessionStore: makeSessionStore()
        )

        await presenter.send(.onAppear)
        XCTAssertEqual(presenter.viewState.nextCursor, "cursor-2")

        await presenter.send(.sortToggleTapped)

        XCTAssertEqual(
            presenter.viewState.selectedSort,
            CommunitySortSelection(category: .latest, direction: .ascending)
        )
        XCTAssertNil(presenter.viewState.nextCursor)
        XCTAssertEqual(
            interactor.loadFeedSorts,
            [
                .latest,
                CommunitySortSelection(category: .latest, direction: .ascending)
            ]
        )

        await presenter.send(.sortToggleTapped)

        XCTAssertEqual(presenter.viewState.selectedSort, .latest)
        XCTAssertNil(presenter.viewState.nextCursor)
        XCTAssertEqual(
            interactor.loadFeedSorts,
            [
                .latest,
                CommunitySortSelection(category: .latest, direction: .ascending),
                .latest
            ]
        )
    }

    func testSortCategoryPillSelectsDefaultDirection() async {
        let interactor = RecordingCommunityInteractor(nextCursors: [nil, nil, nil])
        let presenter = CommunityPresenter(
            interactor: interactor,
            router: CommunityRouter(),
            sessionStore: makeSessionStore()
        )

        await presenter.send(.onAppear)
        await presenter.send(.sortSelected(CommunitySortCategory.popularity.id))
        await presenter.send(.sortSelected(CommunitySortCategory.distance.id))

        XCTAssertEqual(presenter.viewState.selectedSort, .distance)
        XCTAssertEqual(interactor.loadFeedSorts, [.latest, .popular, .distance])
    }

    func testCommunityPostListPresenterRemovesPostWhenLikedListUnlikesItem() async {
        let presenter = CommunityPostListPresenter(
            mode: .liked(category: nil),
            interactor: StubCommunityPostListInteractor(
                initialPage: CursorPage(
                    items: [makePostSummary(id: "post-1", isLiked: true)],
                    nextCursor: nil
                ),
                likeResult: .success(false)
            ),
            router: CommunityPostListRouter()
        )

        await presenter.send(.onAppear)
        await presenter.send(.likeTapped("post-1"))

        XCTAssertTrue(presenter.viewState.posts.isEmpty)
        XCTAssertEqual(presenter.viewState.emptyStateTitle, "좋아요한 글이 없어요")
    }

    func testCommunityPostListPresenterStopsPagingAfterNilNextCursor() async {
        let interactor = StubCommunityPostListInteractor(
            initialPage: CursorPage(
                items: [makePostSummary(id: "post-1")],
                nextCursor: "cursor-2"
            ),
            pagedResults: [
                .success(
                    CursorPage(
                        items: [makePostSummary(id: "post-2")],
                        nextCursor: nil
                    )
                )
            ]
        )
        let presenter = CommunityPostListPresenter(
            mode: .mine(userID: "user-1", category: nil),
            interactor: interactor,
            router: CommunityPostListRouter()
        )

        await presenter.send(.onAppear)
        await presenter.send(.postAppeared("post-1"))
        await presenter.send(.postAppeared("post-2"))

        XCTAssertEqual(interactor.recordedNextCursors, ["cursor-2"])
        XCTAssertNil(presenter.viewState.nextCursor)
    }

    private func makeSessionStore() -> SessionStore {
        SessionStore(
            tokenStore: StubCommunitySessionTokenStore(),
            userDefaultsStore: UserDefaultsStore(userDefaults: UserDefaults(suiteName: #function + UUID().uuidString)!)
        )
    }

    private func makePostSummary(
        id: String,
        isLiked: Bool = false
    ) -> CommunityPostSummary {
        CommunityPostSummary(
            id: id,
            category: "일상",
            title: "제목 \(id)",
            content: "본문 \(id)",
            creator: CommunityPostAuthor(
                id: "user-\(id)",
                nick: "작성자",
                profileImagePath: nil
            ),
            mediaPaths: [],
            store: nil,
            isLiked: isLiked,
            likeCount: isLiked ? 3 : 1,
            longitude: nil,
            latitude: nil,
            createdAt: Date(),
            updatedAt: nil
        )
    }
}

@MainActor
private struct StubCommunityInteractor: CommunityInteracting {
    func loadFeed(
        query: String?,
        selectedDistance: CommunityDistanceOption,
        selectedSort: CommunitySortOption
    ) async throws -> CommunityFeedContent {
        CommunityFeedContent(
            featuredBanner: .mock,
            posts: [],
            nextCursor: nil,
            referenceLocation: nil
        )
    }

    func loadMorePosts(
        selectedDistance: CommunityDistanceOption,
        selectedSort: CommunitySortOption,
        nextCursor: String
    ) async throws -> CommunityFeedContent {
        CommunityFeedContent(
            featuredBanner: .mock,
            posts: [],
            nextCursor: nil,
            referenceLocation: nil
        )
    }

    func loadPost(postID: String) async throws -> CommunityPostSummary {
        CommunityPostSummary(
            id: postID,
            category: "일상",
            title: "제목 \(postID)",
            content: "본문 \(postID)",
            creator: CommunityPostAuthor(
                id: "user-\(postID)",
                nick: "작성자",
                profileImagePath: nil
            ),
            mediaPaths: [],
            store: nil,
            isLiked: false,
            likeCount: 0,
            longitude: nil,
            latitude: nil,
            createdAt: Date(),
            updatedAt: nil
        )
    }

    func updateLikeStatus(postID: String, isLiked: Bool) async throws -> Bool {
        isLiked
    }
}

@MainActor
private final class RecordingCommunityInteractor: CommunityInteracting {
    private(set) var loadFeedSorts: [CommunitySortOption] = []
    private var nextCursors: [String?]

    init(nextCursors: [String?] = []) {
        self.nextCursors = nextCursors
    }

    func loadFeed(
        query: String?,
        selectedDistance: CommunityDistanceOption,
        selectedSort: CommunitySortOption
    ) async throws -> CommunityFeedContent {
        loadFeedSorts.append(selectedSort)
        return CommunityFeedContent(
            featuredBanner: nil,
            posts: [],
            nextCursor: nextCursors.isEmpty ? nil : nextCursors.removeFirst(),
            referenceLocation: nil
        )
    }

    func loadMorePosts(
        selectedDistance: CommunityDistanceOption,
        selectedSort: CommunitySortOption,
        nextCursor: String
    ) async throws -> CommunityFeedContent {
        CommunityFeedContent(
            featuredBanner: nil,
            posts: [],
            nextCursor: nil,
            referenceLocation: nil
        )
    }

    func loadPost(postID: String) async throws -> CommunityPostSummary {
        CommunityPostSummary(
            id: postID,
            category: "일상",
            title: "제목 \(postID)",
            content: "본문 \(postID)",
            creator: CommunityPostAuthor(
                id: "user-\(postID)",
                nick: "작성자",
                profileImagePath: nil
            ),
            mediaPaths: [],
            store: nil,
            isLiked: false,
            likeCount: 0,
            longitude: nil,
            latitude: nil,
            createdAt: Date(),
            updatedAt: nil
        )
    }

    func updateLikeStatus(postID: String, isLiked: Bool) async throws -> Bool {
        isLiked
    }
}

private actor StubCommunitySessionTokenStore: TokenStore {
    func loadTokens() async throws -> StoredTokens? {
        nil
    }

    func saveTokens(_ tokens: StoredTokens) async throws {}

    func clearTokens() async throws {}
}

@MainActor
private final class StubCommunityPostListInteractor: CommunityPostListInteracting {
    let initialPage: CursorPage<CommunityPostSummary>
    var pagedResults: [Result<CursorPage<CommunityPostSummary>, Error>]
    var likeResult: Result<Bool, Error>
    private(set) var recordedNextCursors: [String] = []

    init(
        initialPage: CursorPage<CommunityPostSummary>,
        pagedResults: [Result<CursorPage<CommunityPostSummary>, Error>] = [],
        likeResult: Result<Bool, Error> = .success(true)
    ) {
        self.initialPage = initialPage
        self.pagedResults = pagedResults
        self.likeResult = likeResult
    }

    func loadInitialPosts() async throws -> CursorPage<CommunityPostSummary> {
        initialPage
    }

    func loadMorePosts(nextCursor: String) async throws -> CursorPage<CommunityPostSummary> {
        recordedNextCursors.append(nextCursor)
        return try pagedResults.removeFirst().get()
    }

    func updateLikeStatus(postID: String, isLiked: Bool) async throws -> Bool {
        try likeResult.get()
    }
}
