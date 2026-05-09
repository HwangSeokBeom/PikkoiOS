import CoreLocation
import UIKit
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

        XCTAssertEqual(content.mode, .create)
        XCTAssertEqual(content.navigationTitle, "작성하기")
        XCTAssertEqual(content.selectedCategoryID, "daily")
        XCTAssertFalse(content.categoryOptions.isEmpty)
    }

    func testCommunityComposerInteractorReturnsEditInitialContentFromProvidedDraft() async throws {
        let interactor = CommunityComposerInteractor(
            mode: .edit(postID: "post-123"),
            initialDraft: CommunityComposerDraft(
                title: "기존 제목",
                body: "기존 본문",
                categoryTitle: "픽업후기",
                store: .init(id: "store-1", name: "세삭카페"),
                attachments: [.init(path: "/v1/data/posts/existing.png")],
                latitude: 37.5,
                longitude: 127.0
            ),
            communityRepository: StubCommunityComposerRepository(),
            locationService: StubCommunityComposerLocationService()
        )

        let content = try await interactor.loadInitialContent()

        XCTAssertEqual(content.mode, .edit(postID: "post-123"))
        XCTAssertEqual(content.navigationTitle, "수정하기")
        XCTAssertEqual(content.initialDraft.title, "기존 제목")
        XCTAssertEqual(content.initialDraft.store?.id, "store-1")
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
            draft: CommunityComposerDraft(
                title: "작성 성공",
                body: "실제 create endpoint에 전달되는 본문입니다.",
                categoryTitle: "일상",
                store: nil,
                attachments: [],
                latitude: nil,
                longitude: nil
            )
        )

        XCTAssertEqual(createdPost.summary.id, "created-post")
        XCTAssertEqual(createdPost.summary.title, "작성 성공")
    }

    func testCommunityComposerInteractorUsesSelectedLocationBeforeCurrentLocation() async throws {
        SelectedLocationStore.shared.save(
            PikkoSelectedLocation(
                title: "선택 위치",
                subtitle: nil,
                latitude: 37.5,
                longitude: 127.0
            )
        )
        defer { SelectedLocationStore.shared.clear() }

        let repository = StubCommunityComposerRepository(
            createResult: .success(makeCreatedDetail(postID: "created-post"))
        )
        let interactor = CommunityComposerInteractor(
            communityRepository: repository,
            locationService: StubCommunityComposerLocationService(
                currentLocation: CLLocation(latitude: 35.0, longitude: 129.0)
            )
        )

        _ = try await interactor.submitPost(
            draft: CommunityComposerDraft(
                title: "작성 성공",
                body: "선택 위치 기준으로 등록합니다.",
                categoryTitle: "일상",
                store: nil,
                attachments: [],
                latitude: nil,
                longitude: nil
            )
        )

        XCTAssertEqual(repository.recordedCreateSubmission?.latitude, 37.5)
        XCTAssertEqual(repository.recordedCreateSubmission?.longitude, 127.0)
    }

    func testCommunityComposerInteractorUpdatesPostInEditMode() async throws {
        let repository = StubCommunityComposerRepository(
            updateResult: .success(makeCreatedDetail(postID: "edited-post"))
        )
        let interactor = CommunityComposerInteractor(
            mode: .edit(postID: "edited-post"),
            initialDraft: CommunityComposerDraft(
                title: "기존 제목",
                body: "기존 본문",
                categoryTitle: "일상",
                store: nil,
                attachments: [],
                latitude: 37.654215,
                longitude: 127.049914
            ),
            communityRepository: repository,
            locationService: StubCommunityComposerLocationService()
        )

        let updatedPost = try await interactor.submitPost(
            draft: CommunityComposerDraft(
                title: "수정된 제목",
                body: "수정된 본문",
                categoryTitle: "일상",
                store: nil,
                attachments: [],
                latitude: 37.654215,
                longitude: 127.049914
            )
        )

        XCTAssertEqual(updatedPost.summary.id, "edited-post")
        XCTAssertEqual(repository.recordedUpdatedPostID, "edited-post")
    }

    func testCommunityComposerInteractorNormalizesResolvedAttachmentURLsBeforeUpdate() async throws {
        let repository = StubCommunityComposerRepository(
            updateResult: .success(makeCreatedDetail(postID: "edited-post"))
        )
        let interactor = CommunityComposerInteractor(
            mode: .edit(postID: "edited-post"),
            communityRepository: repository,
            locationService: StubCommunityComposerLocationService()
        )

        _ = try await interactor.submitPost(
            draft: CommunityComposerDraft(
                title: "수정된 제목",
                body: "수정된 본문",
                categoryTitle: "일상",
                store: nil,
                attachments: [
                    .init(path: "http://pickup.sesac.kr:42678/v1/data/posts/existing.png")
                ],
                latitude: 37.654215,
                longitude: 127.049914
            )
        )

        XCTAssertEqual(repository.recordedUpdatedSubmission?.filePaths, ["/data/posts/existing.png"])
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
                draft: CommunityComposerDraft(
                    title: "작성 실패",
                    body: "로그인 필요",
                    categoryTitle: "일상",
                    store: nil,
                    attachments: [],
                    latitude: nil,
                    longitude: nil
                )
            )
            XCTFail("Expected authenticationRequired error")
        } catch let error as CommunityComposerFeatureError {
            XCTAssertEqual(error, .authenticationRequired)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testCommunityComposerPresenterConfiguresCreateModeState() async {
        let router = CommunityComposerRouter()
        let presenter = CommunityComposerPresenter(
            interactor: StubCommunityComposerInteractor(
                loadResult: .success(.create()),
                submitResult: .success(makeCreatedDetail(postID: "post-999"))
            ),
            router: router
        )

        await presenter.send(.onAppear)

        XCTAssertEqual(presenter.viewState.mode, .create)
        XCTAssertEqual(presenter.viewState.navigationTitle, "작성하기")
        XCTAssertEqual(presenter.viewState.submitTitle, "등록")
    }

    func testCommunityComposerPresenterConfiguresEditModeState() async {
        let router = CommunityComposerRouter()
        let presenter = CommunityComposerPresenter(
            interactor: StubCommunityComposerInteractor(
                loadResult: .success(
                    .edit(
                        postID: "post-123",
                        initialDraft: CommunityComposerDraft(
                            title: "기존 제목",
                            body: "기존 본문",
                            categoryTitle: "일상",
                            store: .init(id: "store-1", name: "세삭카페"),
                            attachments: [.init(path: "/v1/data/posts/existing.png")],
                            latitude: 37.5,
                            longitude: 127.0
                        )
                    )
                ),
                submitResult: .success(makeCreatedDetail(postID: "post-123"))
            ),
            router: router
        )

        await presenter.send(.onAppear)

        XCTAssertEqual(presenter.viewState.mode, .edit(postID: "post-123"))
        XCTAssertEqual(presenter.viewState.navigationTitle, "수정하기")
        XCTAssertEqual(presenter.viewState.submitTitle, "저장")
        XCTAssertEqual(presenter.viewState.linkedStoreTitle, "세삭카페")
        XCTAssertEqual(presenter.viewState.attachmentCount, 1)
    }

    func testCommunityComposerPresenterRoutesToDetailOnCreateSuccess() async {
        let router = CommunityComposerRouter()
        let presenter = CommunityComposerPresenter(
            interactor: StubCommunityComposerInteractor(
                loadResult: .success(.create()),
                submitResult: .success(makeCreatedDetail(postID: "post-999"))
            ),
            router: router
        )

        await presenter.send(.onAppear)
        await presenter.send(.titleChanged("새 글"))
        await presenter.send(.bodyChanged("본문"))
        await presenter.send(.submitTapped)

        XCTAssertEqual(presenter.viewState.submittedPostID, "post-999")
        XCTAssertEqual(presenter.viewState.infoMessage, "게시글을 등록했어요.")
        XCTAssertEqual(router.pendingRoute, .communityDetail(postID: "post-999"))
    }

    func testCommunityComposerPresenterRoutesToDetailOnEditSuccess() async {
        let router = CommunityComposerRouter()
        let presenter = CommunityComposerPresenter(
            interactor: StubCommunityComposerInteractor(
                loadResult: .success(
                    .edit(
                        postID: "post-555",
                        initialDraft: CommunityComposerDraft(
                            title: "기존 제목",
                            body: "기존 본문",
                            categoryTitle: "일상",
                            store: nil,
                            attachments: [],
                            latitude: 37.5,
                            longitude: 127.0
                        )
                    )
                ),
                submitResult: .success(makeCreatedDetail(postID: "post-555"))
            ),
            router: router
        )

        await presenter.send(.onAppear)
        await presenter.send(.titleChanged("수정된 제목"))
        await presenter.send(.bodyChanged("수정된 본문"))
        await presenter.send(.submitTapped)

        XCTAssertEqual(presenter.viewState.infoMessage, "게시글을 저장했어요.")
        XCTAssertEqual(router.pendingRoute, .communityDetail(postID: "post-555"))
    }

    func testCommunityComposerPresenterReflectsSubmitFailure() async {
        let router = CommunityComposerRouter()
        let presenter = CommunityComposerPresenter(
            interactor: StubCommunityComposerInteractor(
                loadResult: .success(.create()),
                submitResult: .failure(CommunityComposerFeatureError.validation(message: "필수값을 채워주세요."))
            ),
            router: router
        )

        await presenter.send(.onAppear)
        await presenter.send(.titleChanged("새 글"))
        await presenter.send(.bodyChanged("본문"))
        await presenter.send(.submitTapped)

        XCTAssertEqual(presenter.viewState.serverValidationMessage, "필수값을 채워주세요.")
        XCTAssertEqual(presenter.viewState.errorMessage, "필수값을 채워주세요.")
        XCTAssertNil(router.pendingRoute)
    }

    func testCommunityComposerPresenterBlocksSubmitAfterAttachmentUploadFailure() async {
        let router = CommunityComposerRouter()
        let presenter = CommunityComposerPresenter(
            interactor: StubCommunityComposerInteractor(
                loadResult: .success(.create()),
                uploadResult: .failure(CommunityComposerFeatureError.validation(message: "첨부 파일 형식과 용량을 다시 확인해 주세요.")),
                submitResult: .success(makeCreatedDetail(postID: "post-999"))
            ),
            router: router
        )

        await presenter.send(.onAppear)
        await presenter.send(
            .attachmentsUploadRequested([
                .init(
                    data: Data(repeating: 1, count: 1024),
                    fileName: "sample.jpg",
                    mimeType: "image/jpeg"
                )
            ])
        )
        await presenter.send(.titleChanged("새 글"))
        await presenter.send(.bodyChanged("본문"))
        await presenter.send(.submitTapped)

        XCTAssertEqual(
            presenter.viewState.attachmentUploadErrorMessage,
            "첨부 파일 형식과 용량을 다시 확인해 주세요."
        )
        XCTAssertNil(router.pendingRoute)
    }

    func testMediaUploadPreprocessorKeepsSmallFileUnchanged() throws {
        let file = CommunityPostUploadFile(
            data: Data([1, 2, 3, 4]),
            fileName: "small.jpg",
            mimeType: "image/jpeg"
        )

        let result = try MediaUploadPreprocessor().process(file, maxBytes: 10)

        XCTAssertEqual(result.file, file)
        XCTAssertEqual(result.metadata.originalBytes, 4)
        XCTAssertEqual(result.metadata.finalBytes, 4)
        XCTAssertFalse(result.metadata.wasResized)
    }

    func testMediaUploadPreprocessorCompressesLargeImageUnderLimit() throws {
        let imageData = try XCTUnwrap(makeTestImage(size: CGSize(width: 900, height: 900)).jpegData(compressionQuality: 1.0))
        let file = CommunityPostUploadFile(
            data: imageData,
            fileName: "large.png",
            mimeType: "image/png"
        )

        let result = try MediaUploadPreprocessor().process(file, maxBytes: 35_000)

        XCTAssertLessThanOrEqual(result.file.data.count, 35_000)
        XCTAssertEqual(result.file.mimeType, "image/jpeg")
        XCTAssertEqual(result.file.fileName, "large.jpg")
        XCTAssertTrue(result.metadata.wasResized)
        XCTAssertEqual(result.metadata.originalBytes, imageData.count)
    }

    func testMediaUploadPreprocessorRejectsImageThatCannotFitLimit() throws {
        let imageData = try XCTUnwrap(makeTestImage(size: CGSize(width: 20, height: 20)).jpegData(compressionQuality: 1.0))
        let file = CommunityPostUploadFile(
            data: imageData,
            fileName: "too-large.jpg",
            mimeType: "image/jpeg"
        )

        XCTAssertThrowsError(try MediaUploadPreprocessor().process(file, maxBytes: 1)) { error in
            XCTAssertEqual(error as? MediaUploadPreprocessorError, .fileTooLarge)
            XCTAssertEqual(error.localizedDescription, "파일 크기가 너무 커요. 더 작은 파일을 선택해 주세요.")
        }
    }

    func testMediaUploadPreprocessorRejectsOversizedNonCompressibleMedia() {
        let file = CommunityPostUploadFile(
            data: Data(repeating: 7, count: 12),
            fileName: "large.mp4",
            mimeType: "video/mp4"
        )

        XCTAssertThrowsError(try MediaUploadPreprocessor().process(file, maxBytes: 10)) { error in
            XCTAssertEqual(error as? MediaUploadPreprocessorError, .fileTooLarge)
        }
    }

    func testMediaUploadPreprocessorRejectsUnsupportedPostFileType() {
        let file = CommunityPostUploadFile(
            data: Data(repeating: 7, count: 4),
            fileName: "large.pdf",
            mimeType: "application/pdf"
        )

        XCTAssertThrowsError(try MediaUploadPreprocessor().process(file, maxBytes: 10)) { error in
            XCTAssertEqual(error as? MediaUploadPreprocessorError, .unsupportedType)
        }
    }

    func testCommunityComposerInteractorPreprocessesLargeImageBeforeUpload() async throws {
        let repository = StubCommunityComposerRepository()
        let interactor = CommunityComposerInteractor(
            communityRepository: repository,
            locationService: StubCommunityComposerLocationService()
        )
        let imageData = try XCTUnwrap(makeTestImage(size: CGSize(width: 1400, height: 1400)).jpegData(compressionQuality: 1.0))

        _ = try await interactor.uploadAttachments([
            CommunityPostUploadFile(
                data: imageData,
                fileName: "large.jpg",
                mimeType: "image/jpeg"
            )
        ])

        let uploadedFile = try XCTUnwrap(repository.recordedUploadFiles.first)
        XCTAssertLessThanOrEqual(uploadedFile.data.count, CommunityUploadConfiguration.maxAttachmentBytes)
        XCTAssertLessThan(uploadedFile.data.count, imageData.count)
        XCTAssertEqual(uploadedFile.mimeType, "image/jpeg")
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

private func makeTestImage(size: CGSize) -> UIImage {
    let renderer = UIGraphicsImageRenderer(size: size)
    return renderer.image { context in
        UIColor.systemGreen.setFill()
        context.fill(CGRect(origin: .zero, size: size))

        UIColor.systemOrange.setStroke()
        for offset in stride(from: CGFloat(0), through: size.width, by: 8) {
            let path = UIBezierPath()
            path.move(to: CGPoint(x: offset, y: 0))
            path.addLine(to: CGPoint(x: size.width - offset, y: size.height))
            path.lineWidth = 2
            path.stroke()
        }
    }
}

private final class StubCommunityComposerRepository: CommunityRepository, @unchecked Sendable {
    var uploadResult: Result<[String], Error>
    var createResult: Result<CommunityPostDetail, Error>
    var updateResult: Result<CommunityPostDetail, Error>
    private(set) var recordedUploadFiles: [CommunityPostUploadFile] = []
    private(set) var recordedCreateSubmission: CommunityPostDraftSubmission?
    private(set) var recordedUpdatedPostID: String?
    private(set) var recordedUpdatedSubmission: CommunityPostDraftSubmission?

    init(
        uploadResult: Result<[String], Error> = .success(["/data/posts/uploaded.jpg"]),
        createResult: Result<CommunityPostDetail, Error> = .success(
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
        ),
        updateResult: Result<CommunityPostDetail, Error>? = nil
    ) {
        self.uploadResult = uploadResult
        self.createResult = createResult
        self.updateResult = updateResult ?? createResult
    }

    func uploadPostFiles(_ files: [CommunityPostUploadFile]) async throws -> [String] {
        recordedUploadFiles = files
        return try uploadResult.get()
    }

    func createPost(_ submission: CommunityPostDraftSubmission) async throws -> CommunityPostDetail {
        recordedCreateSubmission = submission
        return try createResult.get()
    }

    func updatePost(postID: String, submission: CommunityPostDraftSubmission) async throws -> CommunityPostDetail {
        recordedUpdatedPostID = postID
        recordedUpdatedSubmission = submission
        return try updateResult.get()
    }

    func deletePost(postID: String) async throws {}

    func fetchPostDetail(postID: String) async throws -> CommunityPostDetail {
        try createResult.get()
    }

    func fetchComments(postID: String, nextCursor: String?, limit: Int) async throws -> CursorPage<CommunityComment> {
        CursorPage(items: [], nextCursor: nil)
    }

    func createComment(postID: String, content: String, parentCommentID: String?) async throws -> CommunityComment {
        CommunityComment(
            id: "comment-created",
            postID: postID,
            parentCommentID: parentCommentID,
            author: CommunityPostAuthor(id: "user-1", nick: "작성자", profileImagePath: nil),
            content: content,
            createdAt: nil,
            updatedAt: nil,
            isMine: true,
            isHidden: false,
            replies: []
        )
    }

    func updateComment(postID: String, commentID: String, content: String) async throws -> CommunityComment {
        CommunityComment(
            id: commentID,
            postID: postID,
            parentCommentID: nil,
            author: CommunityPostAuthor(id: "user-1", nick: "작성자", profileImagePath: nil),
            content: content,
            createdAt: nil,
            updatedAt: nil,
            isMine: true,
            isHidden: false,
            replies: []
        )
    }

    func deleteComment(postID: String, commentID: String) async throws {}

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
    var uploadResult: Result<[String], Error> = .success(["/data/posts/uploaded.jpg"])
    var submitResult: Result<CommunityPostDetail, Error>

    func loadInitialContent() async throws -> CommunityComposerContent {
        try loadResult.get()
    }

    func uploadAttachments(_ files: [CommunityPostUploadFile]) async throws -> [String] {
        try uploadResult.get()
    }

    func submitPost(draft: CommunityComposerDraft) async throws -> CommunityPostDetail {
        try submitResult.get()
    }
}
