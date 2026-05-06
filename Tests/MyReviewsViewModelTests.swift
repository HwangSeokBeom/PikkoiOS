import XCTest
@testable import Pikko

@MainActor
final class MyReviewsViewModelTests: XCTestCase {
    func testInitialLoadSuccess() async {
        let interactor = StubUserReviewListInteractor(
            fetchResults: [
                .success(CursorPage(items: [makeReview(id: "review-1")], nextCursor: "cursor-1"))
            ]
        )
        let presenter = UserReviewListPresenter(
            interactor: interactor,
            router: SpyUserReviewListRouter()
        )

        await presenter.send(.onAppear)

        XCTAssertEqual(presenter.viewState.reviews.map(\.id), ["review-1"])
        XCTAssertEqual(presenter.viewState.nextCursor, "cursor-1")
        XCTAssertTrue(presenter.viewState.canLoadMore)
        XCTAssertNil(presenter.viewState.errorMessage)
    }

    func testEmptyResponseShowsEmptyState() async {
        let interactor = StubUserReviewListInteractor(
            fetchResults: [
                .success(CursorPage(items: [], nextCursor: nil))
            ]
        )
        let presenter = UserReviewListPresenter(
            interactor: interactor,
            router: SpyUserReviewListRouter()
        )

        await presenter.send(.onAppear)

        XCTAssertTrue(presenter.viewState.reviews.isEmpty)
        XCTAssertEqual(presenter.viewState.emptyMessage, "아직 작성한 리뷰가 없어요.")
        XCTAssertFalse(presenter.viewState.canLoadMore)
    }

    func testNetworkFailureShowsRetryableError() async {
        let interactor = StubUserReviewListInteractor(
            fetchResults: [
                .failure(NetworkError.transport)
            ]
        )
        let presenter = UserReviewListPresenter(
            interactor: interactor,
            router: SpyUserReviewListRouter()
        )

        await presenter.send(.onAppear)

        XCTAssertTrue(presenter.viewState.reviews.isEmpty)
        XCTAssertEqual(presenter.viewState.errorMessage, "네트워크 상태를 확인한 뒤 다시 시도해 주세요.")
        XCTAssertNil(presenter.viewState.emptyMessage)
    }

    func testRefreshFailureKeepsPreviousItems() async {
        let interactor = StubUserReviewListInteractor(
            fetchResults: [
                .success(CursorPage(items: [makeReview(id: "review-1")], nextCursor: nil)),
                .failure(NetworkError.transport)
            ]
        )
        let presenter = UserReviewListPresenter(
            interactor: interactor,
            router: SpyUserReviewListRouter()
        )

        await presenter.send(.onAppear)
        await presenter.send(.refreshRequested)

        XCTAssertEqual(presenter.viewState.reviews.map(\.id), ["review-1"])
        XCTAssertEqual(presenter.viewState.errorMessage, "네트워크 상태를 확인한 뒤 다시 시도해 주세요.")
    }

    func testPaginationAppendsWithoutDuplicateIDs() async {
        let interactor = StubUserReviewListInteractor(
            fetchResults: [
                .success(CursorPage(items: [makeReview(id: "review-1")], nextCursor: "cursor-1")),
                .success(CursorPage(items: [makeReview(id: "review-1"), makeReview(id: "review-2")], nextCursor: nil))
            ]
        )
        let presenter = UserReviewListPresenter(
            interactor: interactor,
            router: SpyUserReviewListRouter()
        )

        await presenter.send(.onAppear)
        await presenter.send(.reviewAppeared("review-1"))

        XCTAssertEqual(presenter.viewState.reviews.map(\.id), ["review-1", "review-2"])
        XCTAssertEqual(interactor.requestedCursors, [nil, "cursor-1"])
        XCTAssertFalse(presenter.viewState.canLoadMore)
    }

    private func makeReview(id: String, storeID: String = "store-1") -> UserStoreReview {
        UserStoreReview(
            id: id,
            store: CommunityPostStoreSummary(
                id: storeID,
                category: "카페",
                name: "픽코 카페",
                closeTime: "21:00",
                imagePaths: ["/v1/data/stores/store-1.jpg"],
                isPicchelin: false,
                isLiked: false,
                likeCount: 0,
                hashTags: [],
                totalRating: 4.7,
                totalOrderCount: 12,
                totalReviewCount: 3,
                longitude: nil,
                latitude: nil
            ),
            content: "좋았어요",
            rating: 5,
            imagePaths: ["/v1/data/reviews/\(id).jpg"],
            orderedMenuNames: ["아메리카노"],
            author: StoreReviewAuthor(id: "user-1", nick: "픽코", profileImagePath: nil),
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            updatedAt: nil
        )
    }
}

@MainActor
private final class StubUserReviewListInteractor: UserReviewListInteracting {
    private var fetchResults: [Result<CursorPage<UserStoreReview>, Error>]
    private(set) var requestedCursors: [String?] = []

    init(fetchResults: [Result<CursorPage<UserStoreReview>, Error>]) {
        self.fetchResults = fetchResults
    }

    func fetchReviews(nextCursor: String?) async throws -> CursorPage<UserStoreReview> {
        requestedCursors.append(nextCursor)
        guard !fetchResults.isEmpty else {
            return CursorPage(items: [], nextCursor: nil)
        }
        return try fetchResults.removeFirst().get()
    }

    func deleteReview(storeID: String, reviewID: String) async throws {}
}

@MainActor
private final class SpyUserReviewListRouter: UserReviewListRouting {
    private(set) var routedStoreID: String?
    private(set) var routedReviewContext: ReviewComposerContext?

    func routeToStoreDetail(storeID: String) {
        routedStoreID = storeID
    }

    func routeToReviewComposer(context: ReviewComposerContext) {
        routedReviewContext = context
    }

    func clearPendingRoute() {
        routedStoreID = nil
        routedReviewContext = nil
    }
}
