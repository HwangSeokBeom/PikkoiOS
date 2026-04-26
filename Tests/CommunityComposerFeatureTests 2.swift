import CoreLocation
import XCTest
@testable import Pikko

@MainActor
final class CommunityComposerFeatureTests: XCTestCase {
    func testCommunityComposerInteractorReturnsCreateInitialContent() async throws {
        let interactor = CommunityComposerInteractor(
            communityRepository: StubCommunityComposerRepository(),
            locationService: StubCommunityComposerLocationService()
        )

        let content = try await interactor.loadInitialContent()

        XCTAssertEqual(content.navigationTitle, "글 작성")
        XCTAssertEqual(content.selectedCategoryID, "daily")
        XCTAssertFalse(content.categoryOptions.isEmpty)
    }

    func testCommunityComposerInteractorCreatesPostAndReturnsCreatedIdentifier() async throws {
        let interactor = CommunityComposerInteractor(
            communityRepository: StubCommunityComposerRepository(
                createResult: .success(makeCreatedDetail(postID: "created-post"))
            ),
            locationService: StubCommunityComposerLocationService(
                currentLocation: CLLocation(latitude: 37.654215, longitude: 127.049914)
            )
        )

        let createdPost = try await interactor.submitPost(
            category: "일상",
            title: "작성 성공",
            body: "실제 create endpoint에 전달되는 본문입니다."
        )

        XCTAssertEqual(createdPost.summary.id, "created-post")
        XCTAssertEqual(createdPost.summary.title, "작성 성공")
    }

    func testCommunityComposerInteractorMapsUnauthorizedFailure() async {
        let interactor = CommunityComposerInteractor(
            communityRepository: StubCommunityComposerRepository(
                createResult: .failure(NetworkError.unauthorized)
            ),
            locationService: StubCommunityComposerLocationService(
                currentLocation: CLLocation(latitude: 37.654215, longitude: 127.049914)
            )
        )

        do {
            _ = try await interactor.submitPost(
                category: "일상",
                title: "작성 실패",
                body: "로그인 필요"
            )
            XCTFail("Expected authenticationRequired error")
        } catch let error as CommunityComposerFeatureError {
            XCTAssertEqual(error, .authenticationRequired)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testCommunityComposerPresenterStoresSubmittedPostIdentifierOnSuccess() async {
        let presenter = CommunityComposerPresenter(
            interactor: StubCommunityComposerInteractor(
                loadResult: .success(.create),
                submitResult: .success(makeCreatedDetail(postID: "post-999"))
            )
        )

        await presenter.send(.onAppear)
        await presenter.send(.titleChanged("새 글"))
        await presenter.send(.bodyChanged("본문"))
        await presenter.send(.submitTapped)

        XCTAssertEqual(presenter.viewState.submittedPostID, "post-999")
        XCTAssertEqual(presenter.viewState.infoMessage, "게시글을 등록했어요.")
        XCTAssertNil(presenter.viewState.errorMessage)
    }

    private func makeCreatedDetail(postID: String) -> CommunityPostDetail {
        CommunityPostDetail(
            summary: CommunityPostSummary(
                id: postID,
                category: "일상",
                title: "작성 성공",
                content: "생성된 게시글 본문",
                creator: CommunityPostAuthor(
                    id: "user-1",
                    nick: "작성자",
                    profileImagePath: nil
                ),
                mediaPaths: [],
                store: nil,
                isLiked: false,
                likeCount: 0,
                longitude: 127.049914,
                latitude: 37.654215,
                createdAt: nil,
                updatedAt: nil
            ),
            comments: []
        )
    }
}

private struct StubCommunityComposerRepository: CommunityRepository {
    var createResult: Result<CommunityPostDetail, Error> = .success(
        CommunityPostDetail(
            summary: CommunityPostSummary(
                id: "default-created-post",
                category: "일상",
                title: "Default",
                content: "Default",
                creator: CommunityPostAuthor(
                    id: "user-1",
                    nick: "작성자",
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

    func createPost(_ submission: CommunityPostDraftSubmission) async throws -> CommunityPostDetail {
        try createResult.get()
    }

    func fetchPostDetail(postID: String) async throws -> CommunityPostDetail {
        try createResult.get()
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

    func updateLikeStatus(postID: String, isLiked: Bool) async throws -> Bool {
        false
    }
}

@MainActor
private final class StubCommunityComposerLocationService: LocationServiceProtocol {
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
private struct StubCommunityComposerInteractor: CommunityComposerInteracting {
    var loadResult: Result<CommunityComposerContent, Error>
    var submitResult: Result<CommunityPostDetail, Error>

    func loadInitialContent() async throws -> CommunityComposerContent {
        try loadResult.get()
    }

    func submitPost(category: String, title: String, body: String) async throws -> CommunityPostDetail {
        try submitResult.get()
    }
}
