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
            )
        )

        let content = try await interactor.loadInitialContent()

        XCTAssertEqual(content.detail.summary.id, "post-123")
        XCTAssertEqual(content.detail.comments.count, 1)
        XCTAssertNotNil(content.distanceMeters)
    }

    func testCommunityDetailInteractorMapsUnauthorizedFailure() async {
        let interactor = CommunityDetailInteractor(
            postID: "post-123",
            communityRepository: StubCommunityRepository(
                detailResult: .failure(NetworkError.unauthorized)
            ),
            locationService: StubCommunityDetailLocationService()
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

    private func makeDetail(postID: String) -> CommunityPostDetail {
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
            comments: [
                CommunityPostComment(
                    id: "comment-1",
                    content: "첫 댓글",
                    createdAt: nil,
                    creator: CommunityPostAuthor(
                        id: "user-2",
                        nick: "댓글러",
                        profileImagePath: nil
                    ),
                    replies: []
                )
            ]
        )
    }
}

private struct StubCommunityRepository: CommunityRepository {
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
    var likeResult: Result<Bool, Error> = .success(false)

    func createPost(_ submission: CommunityPostDraftSubmission) async throws -> CommunityPostDetail {
        try detailResult.get()
    }

    func updatePost(postID: String, submission: CommunityPostDraftSubmission) async throws -> CommunityPostDetail {
        try detailResult.get()
    }

    func fetchPostDetail(postID: String) async throws -> CommunityPostDetail {
        try detailResult.get()
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
