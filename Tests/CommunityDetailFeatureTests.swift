import CoreLocation
import XCTest
@testable import Pikko

@MainActor
final class CommunityDetailFeatureTests: XCTestCase {
    func testCommunityDetailInteractorLoadsActualDetailByPostID() async throws {
        let interactor = CommunityDetailInteractor(
            postID: "post-123",
            communityRepository: StubCommunityRepository(
                detailResult: .success(makeDetail(postID: "post-123"))
            ),
            locationService: StubCommunityDetailLocationService(
                currentLocation: CLLocation(latitude: 37.5, longitude: 127.0)
            ),
            sessionStore: makeSessionStore(userID: "user-2")
        )

        let content = try await interactor.loadInitialContent()

        XCTAssertEqual(content.detail.summary.id, "post-123")
        XCTAssertEqual(content.detail.comments.count, 1)
        XCTAssertTrue(content.detail.comments[0].isMine)
        XCTAssertNotNil(content.distanceMeters)
    }

    func testCommunityDetailInteractorMapsUnauthorizedFailure() async {
        let interactor = CommunityDetailInteractor(
            postID: "post-123",
            communityRepository: StubCommunityRepository(
                detailResult: .failure(NetworkError.unauthorized)
            ),
            locationService: StubCommunityDetailLocationService(),
            sessionStore: makeSessionStore()
        )

        do {
            _ = try await interactor.loadInitialContent()
            XCTFail("Expected authenticationRequired error")
        } catch let error as CommunityDetailFeatureError {
            XCTAssertEqual(error, .authenticationRequired)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testCommunityDetailPresenterReflectsInitialCommentsPage() async {
        let presenter = CommunityDetailPresenter(
            postID: "post-123",
            interactor: StubCommunityDetailInteractor(
                loadContentResult: .success(
                    CommunityDetailContent(
                        detail: makeDetail(postID: "post-123", comments: []),
                        distanceMeters: 120
                    )
                ),
                loadCommentsResults: [
                    .success(
                        CursorPage(
                            items: [makeComment(id: "comment-1", postID: "post-123")],
                            nextCursor: "cursor-2"
                        )
                    )
                ]
            ),
            router: CommunityDetailRouter(),
            sessionStore: makeSessionStore()
        )

        await presenter.send(.onAppear)

        XCTAssertEqual(presenter.viewState.commentSection.comments.count, 1)
        XCTAssertEqual(presenter.viewState.commentSection.countText, "댓글 1개")
        XCTAssertEqual(presenter.viewState.commentSection.nextCursor, "cursor-2")
        XCTAssertTrue(presenter.viewState.commentSection.canLoadMore)
    }

    func testCommunityDetailPresenterKeepsDetailWhenCommentsFail() async {
        let presenter = CommunityDetailPresenter(
            postID: "post-123",
            interactor: StubCommunityDetailInteractor(
                loadContentResult: .success(
                    CommunityDetailContent(
                        detail: makeDetail(postID: "post-123", comments: []),
                        distanceMeters: 80
                    )
                ),
                loadCommentsResults: [
                    .failure(CommunityDetailCommentFeatureError.unavailable(message: "댓글을 불러오지 못했어요."))
                ]
            ),
            router: CommunityDetailRouter(),
            sessionStore: makeSessionStore()
        )

        await presenter.send(.onAppear)

        XCTAssertTrue(presenter.viewState.hasLoadedContent)
        XCTAssertEqual(presenter.viewState.heroTitle, "실제 상세 제목")
        XCTAssertNil(presenter.viewState.emptyState)
        XCTAssertEqual(presenter.viewState.commentSection.errorMessage, "댓글을 불러오지 못했어요.")
    }

    func testCommunityDetailPresenterPreventsDuplicateLoadMoreCalls() async {
        let interactor = StubCommunityDetailInteractor(
            loadContentResult: .success(
                CommunityDetailContent(
                    detail: makeDetail(postID: "post-123", comments: []),
                    distanceMeters: nil
                )
            ),
            loadCommentsResults: [
                .success(
                    CursorPage(
                        items: [makeComment(id: "comment-1", postID: "post-123")],
                        nextCursor: "cursor-2"
                    )
                ),
                .success(
                    CursorPage(
                        items: [makeComment(id: "comment-2", postID: "post-123")],
                        nextCursor: nil
                    )
                )
            ],
            loadCommentsDelayNanos: 100_000_000
        )
        let presenter = CommunityDetailPresenter(
            postID: "post-123",
            interactor: interactor,
            router: CommunityDetailRouter(),
            sessionStore: makeSessionStore()
        )

        await presenter.send(.onAppear)

        async let first: Void = presenter.send(.commentLoadMoreIfNeeded("comment-1"))
        async let second: Void = presenter.send(.commentLoadMoreIfNeeded("comment-1"))
        _ = await (first, second)

        XCTAssertEqual(interactor.recordedCommentCursors, [nil, "cursor-2"])
    }

    func testCommunityDetailPresenterDeduplicatesLoadMoreComments() async {
        let presenter = CommunityDetailPresenter(
            postID: "post-123",
            interactor: StubCommunityDetailInteractor(
                loadContentResult: .success(
                    CommunityDetailContent(
                        detail: makeDetail(postID: "post-123", comments: []),
                        distanceMeters: nil
                    )
                ),
                loadCommentsResults: [
                    .success(
                        CursorPage(
                            items: [makeComment(id: "comment-1", postID: "post-123")],
                            nextCursor: "cursor-2"
                        )
                    ),
                    .success(
                        CursorPage(
                            items: [
                                makeComment(id: "comment-1", postID: "post-123"),
                                makeComment(id: "comment-2", postID: "post-123")
                            ],
                            nextCursor: nil
                        )
                    )
                ]
            ),
            router: CommunityDetailRouter(),
            sessionStore: makeSessionStore()
        )

        await presenter.send(.onAppear)
        await presenter.send(.commentLoadMoreIfNeeded("comment-1"))

        XCTAssertEqual(presenter.viewState.commentSection.comments.map(\.id), ["comment-1", "comment-2"])
    }

    func testGuestCommentSubmitRoutesToAuthAndPreservesDraft() async {
        let router = CommunityDetailRouter()
        let presenter = CommunityDetailPresenter(
            postID: "post-123",
            interactor: StubCommunityDetailInteractor(
                loadContentResult: .success(
                    CommunityDetailContent(
                        detail: makeDetail(postID: "post-123", comments: []),
                        distanceMeters: nil
                    )
                ),
                loadCommentsResults: [.success(CursorPage(items: [], nextCursor: nil))]
            ),
            router: router,
            sessionStore: makeSessionStore()
        )

        await presenter.send(.onAppear)
        await presenter.send(.commentComposerChanged("로그인 전 draft"))
        await presenter.send(.commentSubmitTapped)

        XCTAssertTrue(router.isAuthPresented)
        XCTAssertEqual(router.authPresentationContext, .communityComment)
        XCTAssertEqual(presenter.viewState.commentSection.composerText, "로그인 전 draft")
        XCTAssertTrue(presenter.viewState.commentSection.requiresAuthentication)
    }

    func testCommunityDetailPresenterCreatesCommentAndClearsInput() async {
        let presenter = CommunityDetailPresenter(
            postID: "post-123",
            interactor: StubCommunityDetailInteractor(
                loadContentResult: .success(
                    CommunityDetailContent(
                        detail: makeDetail(postID: "post-123", comments: []),
                        distanceMeters: nil
                    )
                ),
                loadCommentsResults: [.success(CursorPage(items: [], nextCursor: nil))],
                createCommentResult: .success(
                    makeComment(id: "new-comment", postID: "post-123", isMine: true)
                )
            ),
            router: CommunityDetailRouter(),
            sessionStore: makeSessionStore(userID: "me")
        )

        await presenter.send(.onAppear)
        await presenter.send(.commentComposerChanged("새 댓글"))
        await presenter.send(.commentSubmitTapped)

        XCTAssertEqual(presenter.viewState.commentSection.comments.first?.id, "new-comment")
        XCTAssertEqual(presenter.viewState.commentSection.composerText, "")
        XCTAssertNil(presenter.viewState.commentSection.errorMessage)
    }

    func testCommunityDetailPresenterReflectsCommentSubmitFailure() async {
        let presenter = CommunityDetailPresenter(
            postID: "post-123",
            interactor: StubCommunityDetailInteractor(
                loadContentResult: .success(
                    CommunityDetailContent(
                        detail: makeDetail(postID: "post-123", comments: []),
                        distanceMeters: nil
                    )
                ),
                loadCommentsResults: [.success(CursorPage(items: [], nextCursor: nil))],
                createCommentResult: .failure(
                    CommunityDetailCommentFeatureError.validation(message: "필수값을 채워주세요.")
                )
            ),
            router: CommunityDetailRouter(),
            sessionStore: makeSessionStore(userID: "me")
        )

        await presenter.send(.onAppear)
        await presenter.send(.commentComposerChanged("실패 댓글"))
        await presenter.send(.commentSubmitTapped)

        XCTAssertEqual(presenter.viewState.commentSection.errorMessage, "필수값을 채워주세요.")
        XCTAssertEqual(presenter.viewState.commentSection.composerText, "실패 댓글")
    }

    func testCommunityDetailPresenterUpdatesEditedCommentRow() async {
        let presenter = CommunityDetailPresenter(
            postID: "post-123",
            interactor: StubCommunityDetailInteractor(
                loadContentResult: .success(
                    CommunityDetailContent(
                        detail: makeDetail(postID: "post-123", comments: [makeComment(id: "comment-1", postID: "post-123", isMine: true)]),
                        distanceMeters: nil
                    )
                ),
                loadCommentsResults: [.success(CursorPage(items: [makeComment(id: "comment-1", postID: "post-123", isMine: true)], nextCursor: nil))],
                updateCommentResult: .success(makeComment(id: "comment-1", postID: "post-123", content: "수정된 댓글", isMine: true))
            ),
            router: CommunityDetailRouter(),
            sessionStore: makeSessionStore(userID: "me")
        )

        await presenter.send(.onAppear)
        await presenter.send(.commentEditTapped("comment-1"))
        await presenter.send(.commentEditDraftChanged("수정된 댓글"))
        await presenter.send(.commentEditSaveTapped)

        XCTAssertEqual(presenter.viewState.commentSection.comments.first?.content, "수정된 댓글")
        XCTAssertNil(presenter.viewState.commentSection.editingCommentID)
    }

    func testCommunityDetailPresenterRemovesDeletedCommentRow() async {
        let presenter = CommunityDetailPresenter(
            postID: "post-123",
            interactor: StubCommunityDetailInteractor(
                loadContentResult: .success(
                    CommunityDetailContent(
                        detail: makeDetail(postID: "post-123", comments: [makeComment(id: "comment-1", postID: "post-123", isMine: true)]),
                        distanceMeters: nil
                    )
                ),
                loadCommentsResults: [.success(CursorPage(items: [makeComment(id: "comment-1", postID: "post-123", isMine: true)], nextCursor: nil))],
                deleteCommentResult: .success(())
            ),
            router: CommunityDetailRouter(),
            sessionStore: makeSessionStore(userID: "me")
        )

        await presenter.send(.onAppear)
        await presenter.send(.commentDeleteConfirmed("comment-1"))

        XCTAssertTrue(presenter.viewState.commentSection.comments.isEmpty)
    }

    func testCommunityDetailPresenterRoutesOwnedPostToEditComposer() async {
        let router = CommunityDetailRouter()
        let presenter = CommunityDetailPresenter(
            postID: "post-123",
            interactor: StubCommunityDetailInteractor(
                loadContentResult: .success(
                    CommunityDetailContent(
                        detail: makeDetail(postID: "post-123", comments: []),
                        distanceMeters: nil
                    )
                ),
                loadCommentsResults: [.success(CursorPage(items: [], nextCursor: nil))]
            ),
            router: router,
            sessionStore: makeSessionStore(userID: "user-1")
        )

        await presenter.send(.onAppear)
        await presenter.send(.postEditTapped)

        guard case let .communityComposer(mode, initialDraft) = router.pendingRoute else {
            return XCTFail("Expected composer route")
        }

        XCTAssertEqual(mode, .edit(postID: "post-123"))
        XCTAssertEqual(initialDraft?.title, "실제 상세 제목")
    }

    func testCommunityDetailPresenterDismissesAfterDeletingOwnedPost() async {
        let router = CommunityDetailRouter()
        let presenter = CommunityDetailPresenter(
            postID: "post-123",
            interactor: StubCommunityDetailInteractor(
                loadContentResult: .success(
                    CommunityDetailContent(
                        detail: makeDetail(postID: "post-123", comments: []),
                        distanceMeters: nil
                    )
                ),
                loadCommentsResults: [.success(CursorPage(items: [], nextCursor: nil))],
                deletePostResult: .success(())
            ),
            router: router,
            sessionStore: makeSessionStore(userID: "user-1")
        )

        await presenter.send(.onAppear)
        await presenter.send(.postDeleteConfirmed)

        XCTAssertTrue(router.dismissRequested)
        XCTAssertFalse(presenter.viewState.isDeletingPost)
    }

    func testCommunityDetailInteractorMapsDeletePermissionError() async {
        let interactor = CommunityDetailInteractor(
            postID: "post-123",
            communityRepository: StubCommunityRepository(
                deletePostResult: .failure(NetworkError.businessAuthorization(message: "게시글 삭제 권한이 없습니다."))
            ),
            locationService: StubCommunityDetailLocationService(),
            sessionStore: makeSessionStore(userID: "other-user")
        )

        do {
            try await interactor.deletePost()
            XCTFail("Expected delete failure")
        } catch let error as CommunityDetailFeatureError {
            XCTAssertEqual(error, .unavailable(message: "작성자만 수정/삭제할 수 있습니다."))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    private func makeDetail(postID: String, comments: [CommunityComment] = [CommunityComment(
        id: "comment-1",
        postID: "post-123",
        parentCommentID: nil,
        author: CommunityPostAuthor(
            id: "user-2",
            nick: "댓글러",
            profileImagePath: nil
        ),
        content: "첫 댓글",
        createdAt: nil,
        updatedAt: nil,
        isMine: false,
        isHidden: false,
        replies: []
    )]) -> CommunityPostDetail {
        CommunityPostDetail(
            summary: CommunityPostSummary(
                id: postID,
                category: "디저트",
                title: "실제 상세 제목",
                content: "실제 상세 내용",
                creator: CommunityPostAuthor(
                    id: "user-1",
                    nick: "새싹",
                    profileImagePath: "/v1/data/profiles/avatar.jpg"
                ),
                mediaPaths: ["/v1/data/posts/post.jpg"],
                store: nil,
                isLiked: false,
                likeCount: 4,
                longitude: 127.01,
                latitude: 37.51,
                createdAt: nil,
                updatedAt: nil
            ),
            comments: comments
        )
    }

    private func makeComment(
        id: String,
        postID: String,
        content: String = "댓글 본문",
        isMine: Bool = false
    ) -> CommunityComment {
        CommunityComment(
            id: id,
            postID: postID,
            parentCommentID: nil,
            author: CommunityPostAuthor(
                id: isMine ? "me" : "other",
                nick: isMine ? "나" : "댓글러",
                profileImagePath: nil
            ),
            content: content,
            createdAt: Date(),
            updatedAt: nil,
            isMine: isMine,
            isHidden: false,
            replies: []
        )
    }

    private func makeSessionStore(userID: String? = nil) -> SessionStore {
        let userDefaults = UserDefaults(suiteName: #function + UUID().uuidString)!
        userDefaults.removePersistentDomain(forName: #function + UUID().uuidString)
        let store = SessionStore(
            tokenStore: StubSessionTokenStore(),
            userDefaultsStore: UserDefaultsStore(userDefaults: userDefaults)
        )

        if let userID {
            store.apply(
                session: UserSession(
                    userID: userID,
                    email: "\(userID)@example.com",
                    displayName: "테스트 사용자",
                    profileImagePath: nil,
                    accessToken: "access-token",
                    refreshToken: "refresh-token"
                )
            )
        }

        return store
    }
}

private struct StubCommunityRepository: CommunityRepository {
    var uploadResult: Result<[String], Error> = .success([])
    var detailResult: Result<CommunityPostDetail, Error> = .success(
        CommunityPostDetail(
            summary: CommunityPostSummary(
                id: "default-post",
                category: nil,
                title: "Default",
                content: "Default",
                creator: CommunityPostAuthor(
                    id: "default-user",
                    nick: "Default",
                    profileImagePath: nil
                ),
                mediaPaths: [],
                store: nil,
                isLiked: false,
                likeCount: 0,
                longitude: nil,
                latitude: nil,
                createdAt: nil,
                updatedAt: nil
            ),
            comments: []
        )
    )
    var commentsResult: Result<CursorPage<CommunityComment>, Error> = .success(CursorPage(items: [], nextCursor: nil))
    var createCommentResult: Result<CommunityComment, Error> = .success(
        CommunityComment(
            id: "comment-created",
            postID: "default-post",
            parentCommentID: nil,
            author: CommunityPostAuthor(id: "default-user", nick: "Default", profileImagePath: nil),
            content: "created",
            createdAt: nil,
            updatedAt: nil,
            isMine: false,
            isHidden: false,
            replies: []
        )
    )
    var updateCommentResult: Result<CommunityComment, Error> = .success(
        CommunityComment(
            id: "comment-updated",
            postID: "default-post",
            parentCommentID: nil,
            author: CommunityPostAuthor(id: "default-user", nick: "Default", profileImagePath: nil),
            content: "updated",
            createdAt: nil,
            updatedAt: nil,
            isMine: false,
            isHidden: false,
            replies: []
        )
    )
    var deleteCommentResult: Result<Void, Error> = .success(())
    var deletePostResult: Result<Void, Error> = .success(())
    var likeResult: Result<Bool, Error> = .success(false)

    func uploadPostFiles(_ files: [CommunityPostUploadFile]) async throws -> [String] {
        try uploadResult.get()
    }

    func createPost(_ submission: CommunityPostDraftSubmission) async throws -> CommunityPostDetail {
        try detailResult.get()
    }

    func updatePost(postID: String, submission: CommunityPostDraftSubmission) async throws -> CommunityPostDetail {
        try detailResult.get()
    }

    func deletePost(postID: String) async throws {
        _ = try deletePostResult.get()
    }

    func fetchPostDetail(postID: String) async throws -> CommunityPostDetail {
        try detailResult.get()
    }

    func fetchComments(postID: String, nextCursor: String?, limit: Int) async throws -> CursorPage<CommunityComment> {
        try commentsResult.get()
    }

    func createComment(postID: String, content: String, parentCommentID: String?) async throws -> CommunityComment {
        try createCommentResult.get()
    }

    func updateComment(postID: String, commentID: String, content: String) async throws -> CommunityComment {
        try updateCommentResult.get()
    }

    func deleteComment(postID: String, commentID: String) async throws {
        _ = try deleteCommentResult.get()
    }

    func fetchGeolocationPosts(
        category: String?,
        longitude: Double?,
        latitude: Double?,
        maxDistance: Double?,
        nextCursor: String?,
        limit: Int,
        orderBy: CommunityPostSortOrder
    ) async throws -> CursorPage<CommunityPostSummary> {
        CursorPage(items: [], nextCursor: nil)
    }

    func searchPosts(title: String) async throws -> [CommunityPostSummary] {
        []
    }

    func fetchUserPosts(
        userID: String,
        category: String?,
        nextCursor: String?,
        limit: Int
    ) async throws -> CursorPage<CommunityPostSummary> {
        CursorPage(items: [], nextCursor: nil)
    }

    func fetchLikedPosts(
        category: String?,
        nextCursor: String?,
        limit: Int
    ) async throws -> CursorPage<CommunityPostSummary> {
        CursorPage(items: [], nextCursor: nil)
    }

    func updateLikeStatus(postID: String, isLiked: Bool) async throws -> Bool {
        try likeResult.get()
    }
}

@MainActor
private final class StubCommunityDetailLocationService: LocationServiceProtocol {
    var authorizationStatus: CLAuthorizationStatus = .authorizedWhenInUse
    var currentLocation: CLLocation?

    init(currentLocation: CLLocation? = nil) {
        self.currentLocation = currentLocation
    }

    func requestWhenInUseAuthorization() {}

    func requestCurrentLocation() async throws -> CLLocation {
        if let currentLocation {
            return currentLocation
        }
        throw LocationServiceError.noLocationAvailable
    }

    func startUpdatingLocation() {}

    func stopUpdatingLocation() {}

    func locationUpdates() -> AsyncStream<CLLocation> {
        AsyncStream { continuation in
            continuation.finish()
        }
    }
}

@MainActor
private final class StubCommunityDetailInteractor: CommunityDetailInteracting {
    var loadContentResult: Result<CommunityDetailContent, Error>
    var loadCommentsResults: [Result<CursorPage<CommunityComment>, Error>]
    var deletePostResult: Result<Void, Error>
    var createCommentResult: Result<CommunityComment, Error>
    var updateCommentResult: Result<CommunityComment, Error>
    var deleteCommentResult: Result<Void, Error>
    var likeResult: Result<Bool, Error>
    var loadCommentsDelayNanos: UInt64
    private(set) var recordedCommentCursors: [String?] = []

    init(
        loadContentResult: Result<CommunityDetailContent, Error>,
        loadCommentsResults: [Result<CursorPage<CommunityComment>, Error>] = [.success(CursorPage(items: [], nextCursor: nil))],
        deletePostResult: Result<Void, Error> = .success(()),
        createCommentResult: Result<CommunityComment, Error> = .success(
            CommunityComment(
                id: "created-comment",
                postID: "post-123",
                parentCommentID: nil,
                author: CommunityPostAuthor(id: "me", nick: "나", profileImagePath: nil),
                content: "created",
                createdAt: Date(),
                updatedAt: nil,
                isMine: true,
                isHidden: false,
                replies: []
            )
        ),
        updateCommentResult: Result<CommunityComment, Error> = .success(
            CommunityComment(
                id: "comment-1",
                postID: "post-123",
                parentCommentID: nil,
                author: CommunityPostAuthor(id: "me", nick: "나", profileImagePath: nil),
                content: "updated",
                createdAt: Date(),
                updatedAt: Date(),
                isMine: true,
                isHidden: false,
                replies: []
            )
        ),
        deleteCommentResult: Result<Void, Error> = .success(()),
        likeResult: Result<Bool, Error> = .success(false),
        loadCommentsDelayNanos: UInt64 = 0
    ) {
        self.loadContentResult = loadContentResult
        self.loadCommentsResults = loadCommentsResults
        self.deletePostResult = deletePostResult
        self.createCommentResult = createCommentResult
        self.updateCommentResult = updateCommentResult
        self.deleteCommentResult = deleteCommentResult
        self.likeResult = likeResult
        self.loadCommentsDelayNanos = loadCommentsDelayNanos
    }

    func loadInitialContent() async throws -> CommunityDetailContent {
        try loadContentResult.get()
    }

    func deletePost() async throws {
        _ = try deletePostResult.get()
    }

    func loadComments(nextCursor: String?) async throws -> CursorPage<CommunityComment> {
        recordedCommentCursors.append(nextCursor)
        if loadCommentsDelayNanos > 0 {
            try? await Task.sleep(nanoseconds: loadCommentsDelayNanos)
        }
        return try loadCommentsResults.removeFirst().get()
    }

    func createComment(content: String) async throws -> CommunityComment {
        try createCommentResult.get()
    }

    func updateComment(commentID: String, content: String) async throws -> CommunityComment {
        try updateCommentResult.get()
    }

    func deleteComment(commentID: String) async throws {
        _ = try deleteCommentResult.get()
    }

    func updateLikeStatus(isLiked: Bool) async throws -> Bool {
        try likeResult.get()
    }
}

private actor StubSessionTokenStore: TokenStore {
    func loadTokens() async throws -> StoredTokens? { nil }
    func saveTokens(_ tokens: StoredTokens) async throws {}
    func clearTokens() async throws {}
}
