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
