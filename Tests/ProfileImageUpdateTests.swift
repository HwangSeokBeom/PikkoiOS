import XCTest
import UIKit
@testable import Pikko

@MainActor
final class ProfileImageUpdateTests: XCTestCase {
    func testProfileImagePreprocessorReturnsSupportedImageUnderOneMegabyte() throws {
        let image = makeTestImage(size: CGSize(width: 1600, height: 1600))
        let data = try XCTUnwrap(image.jpegData(compressionQuality: 1.0))

        let result = try ProfileImagePreprocessor().process(data: data, originalFileName: "avatar.png")

        XCTAssertLessThanOrEqual(result.data.count, ProfileImagePreprocessor.targetBytes)
        XCTAssertEqual(result.mimeType, "image/jpeg")
        XCTAssertEqual((result.fileName as NSString).pathExtension, "jpg")
        XCTAssertEqual(result.fileName, "profile.jpg")
    }

    func testHeicNamedInputIsNormalizedToJpeg() throws {
        let image = makeTestImage(size: CGSize(width: 900, height: 700))
        let data = try XCTUnwrap(image.jpegData(compressionQuality: 0.95))

        let result = try ProfileImagePreprocessor().process(data: data, originalFileName: "avatar.heic")

        XCTAssertEqual(result.mimeType, "image/jpeg")
        XCTAssertEqual((result.fileName as NSString).pathExtension, "jpg")
        XCTAssertLessThanOrEqual(result.data.count, ProfileImagePreprocessor.targetBytes)
    }

    func testSmallPNGInputCanRemainPNGUnderLimit() throws {
        let image = makeTestImage(size: CGSize(width: 300, height: 300))
        let data = try XCTUnwrap(image.pngData())

        let result = try ProfileImagePreprocessor().process(data: data, originalFileName: "avatar.png")

        XCTAssertLessThanOrEqual(result.data.count, ProfileImagePreprocessor.maxBytes)
        XCTAssertEqual(result.mimeType, "image/png")
        XCTAssertEqual(result.fileName, "profile.png")
        XCTAssertEqual((result.fileName as NSString).pathExtension, "png")
    }

    func testOversizedImageIsDownsampledBelowLimit() throws {
        let image = makeTestImage(size: CGSize(width: 4_000, height: 3_000))
        let data = try XCTUnwrap(image.jpegData(compressionQuality: 1.0))

        let result = try ProfileImagePreprocessor().process(data: data, originalFileName: "large.jpg")

        XCTAssertLessThanOrEqual(result.data.count, ProfileImagePreprocessor.targetBytes)
        XCTAssertLessThanOrEqual(max(result.pixelSize.width, result.pixelSize.height), 1_024)
    }

    func testOrientationImageNormalizationDoesNotFail() throws {
        let base = makeTestImage(size: CGSize(width: 640, height: 480))
        let cgImage = try XCTUnwrap(base.cgImage)
        let rotated = UIImage(cgImage: cgImage, scale: 1, orientation: .right)
        let data = try XCTUnwrap(rotated.jpegData(compressionQuality: 0.9))

        let result = try ProfileImagePreprocessor().process(data: data, originalFileName: "rotated.jpg")

        XCTAssertEqual(result.mimeType, "image/jpeg")
        XCTAssertFalse(result.data.isEmpty)
    }

    func testUnsupportedDataReturnsClearFailure() {
        XCTAssertThrowsError(
            try ProfileImagePreprocessor().process(data: Data("not-image".utf8), originalFileName: "avatar.jpg")
        ) { error in
            XCTAssertEqual(error as? ProfileImagePreprocessorError, .decodeFailed)
        }
    }

    func testUploadProfileImageReturnsAbsoluteResolvedImageURL() async throws {
        let remote = StubProfileAuthRemoteDataSource()
        let repository = AuthRepositoryImpl(
            remoteDataSource: remote,
            tokenStore: StubProfileTokenStore(),
            sessionSnapshotStore: StubProfileSessionSnapshotStore(),
            fileURLResolver: StubProfileFileURLResolver()
        )

        let path = try await repository.uploadProfileImage(
            data: Data("image".utf8),
            fileName: "profile.jpg",
            mimeType: "image/jpeg"
        )

        XCTAssertEqual(path, "https://example.com/data/profiles/uploaded.jpg")
        XCTAssertEqual(remote.uploadedFieldFileName, "profile.jpg")
        XCTAssertEqual(remote.uploadedMimeType, "image/jpeg")
    }

    func testUpdateProfileDoesNotSendProfileImagePath() async throws {
        let remote = StubProfileAuthRemoteDataSource()
        let repository = AuthRepositoryImpl(
            remoteDataSource: remote,
            tokenStore: StubProfileTokenStore(),
            sessionSnapshotStore: StubProfileSessionSnapshotStore(),
            fileURLResolver: StubProfileFileURLResolver()
        )

        _ = try await repository.updateMyProfile(
            nick: "픽코",
            phoneNumber: "01012345678"
        )

        XCTAssertEqual(remote.updatedNick, "픽코")
        XCTAssertEqual(remote.updatedPhoneNumber, "01012345678")
    }

    func testProfilePresenterUploadSuccessUpdatesEditorStateAndInvalidatesCache() async throws {
        let sessionStore = makeAuthenticatedSessionStore()
        let interactor = StubProfileInteractor()
        let imageLoader = StubProfileImageLoader()
        let presenter = ProfilePresenter(
            interactor: interactor,
            router: StubProfileRouter(),
            sessionStore: sessionStore,
            imageLoader: imageLoader
        )
        let data = try XCTUnwrap(makeTestImage(size: CGSize(width: 500, height: 500)).jpegData(compressionQuality: 0.9))

        await presenter.send(.editProfileTapped)
        await presenter.send(.profileImageDataSelected(data, fileName: "avatar.heic"))

        XCTAssertEqual(presenter.viewState.editorProfileImagePath, interactor.uploadedPath)
        XCTAssertEqual(presenter.viewState.profileImagePath, interactor.uploadedPath)
        XCTAssertEqual(sessionStore.profileImagePath, interactor.uploadedPath)
        XCTAssertNil(presenter.viewState.editorLocalProfileImageData)
        XCTAssertNil(presenter.viewState.profileImageUploadErrorMessage)
        XCTAssertEqual(presenter.viewState.profileImageUpdateState, .success)
        let removedPaths = await imageLoader.removedPathsSnapshot()
        XCTAssertEqual(Set(removedPaths), Set(["https://example.com/old.jpg", interactor.uploadedPath]))
    }

    func testProfilePresenterUploadFailurePreservesPreviousImage() async throws {
        let sessionStore = makeAuthenticatedSessionStore()
        let interactor = StubProfileInteractor()
        interactor.uploadError = NetworkError.transport
        let presenter = ProfilePresenter(
            interactor: interactor,
            router: StubProfileRouter(),
            sessionStore: sessionStore,
            imageLoader: StubProfileImageLoader()
        )
        let data = try XCTUnwrap(makeTestImage(size: CGSize(width: 500, height: 500)).jpegData(compressionQuality: 0.9))

        await presenter.send(.editProfileTapped)
        let originalPath = presenter.viewState.editorProfileImagePath
        await presenter.send(.profileImageDataSelected(data, fileName: "avatar.jpg"))

        XCTAssertEqual(presenter.viewState.editorProfileImagePath, originalPath)
        XCTAssertEqual(presenter.viewState.profileImagePath, originalPath)
        XCTAssertEqual(sessionStore.profileImagePath, originalPath)
        XCTAssertNotNil(presenter.viewState.profileImageUploadErrorMessage)
        XCTAssertNil(presenter.viewState.editorLocalProfileImageData)
    }

    func testStaleProfileLoadDoesNotOverwriteNewUploadedAvatar() async throws {
        let sessionStore = makeAuthenticatedSessionStore()
        let interactor = StubProfileInteractor()
        interactor.holdInitialLoad = true
        let presenter = ProfilePresenter(
            interactor: interactor,
            router: StubProfileRouter(),
            sessionStore: sessionStore,
            imageLoader: StubProfileImageLoader()
        )
        let data = try XCTUnwrap(makeTestImage(size: CGSize(width: 500, height: 500)).jpegData(compressionQuality: 0.9))

        let loadTask = Task { await presenter.send(.onAppear) }
        await interactor.waitForLoadStarted()
        await presenter.send(.editProfileTapped)
        await presenter.send(.profileImageDataSelected(data, fileName: "avatar.jpg"))
        interactor.releaseInitialLoad()
        await loadTask.value

        XCTAssertEqual(presenter.viewState.editorProfileImagePath, interactor.uploadedPath)
    }

    func testStaleProfileRefetchCannotOverwriteNewUploadedAvatar() async throws {
        let sessionStore = makeAuthenticatedSessionStore()
        let interactor = StubProfileInteractor()
        interactor.profileRefetchPath = "https://example.com/old.jpg"
        let imageLoader = StubProfileImageLoader()
        let presenter = ProfilePresenter(
            interactor: interactor,
            router: StubProfileRouter(),
            sessionStore: sessionStore,
            imageLoader: imageLoader
        )
        let data = try XCTUnwrap(makeTestImage(size: CGSize(width: 500, height: 500)).jpegData(compressionQuality: 0.9))

        await presenter.send(.editProfileTapped)
        await presenter.send(.profileImageDataSelected(data, fileName: "avatar.jpg"))

        XCTAssertEqual(presenter.viewState.profileImagePath, interactor.uploadedPath)
        XCTAssertEqual(sessionStore.profileImagePath, interactor.uploadedPath)
    }

    func testFailedImageURLCacheIsClearedAfterProfileImageUpdate() async throws {
        let sessionStore = makeAuthenticatedSessionStore()
        let interactor = StubProfileInteractor()
        let imageLoader = StubProfileImageLoader()
        let presenter = ProfilePresenter(
            interactor: interactor,
            router: StubProfileRouter(),
            sessionStore: sessionStore,
            imageLoader: imageLoader
        )
        let data = try XCTUnwrap(makeTestImage(size: CGSize(width: 500, height: 500)).jpegData(compressionQuality: 0.9))

        await presenter.send(.editProfileTapped)
        await presenter.send(.profileImageDataSelected(data, fileName: "avatar.jpg"))

        let removedPaths = await imageLoader.removedPathsSnapshot()
        XCTAssertTrue(removedPaths.contains("https://example.com/old.jpg"))
        XCTAssertTrue(removedPaths.contains(interactor.uploadedPath))
    }

    func testDuplicateProfileImageUploadTapIsIgnoredWhileUploadInProgress() async throws {
        let sessionStore = makeAuthenticatedSessionStore()
        let interactor = StubProfileInteractor()
        interactor.holdUpload = true
        let presenter = ProfilePresenter(
            interactor: interactor,
            router: StubProfileRouter(),
            sessionStore: sessionStore,
            imageLoader: StubProfileImageLoader()
        )
        let data = try XCTUnwrap(makeTestImage(size: CGSize(width: 500, height: 500)).jpegData(compressionQuality: 0.9))

        await presenter.send(.editProfileTapped)
        let firstUpload = Task { await presenter.send(.profileImageDataSelected(data, fileName: "avatar.jpg")) }
        await interactor.waitForUploadStarted()
        await presenter.send(.profileImageDataSelected(data, fileName: "avatar.jpg"))
        XCTAssertEqual(interactor.uploadCallCount, 1)

        interactor.releaseUpload()
        await firstUpload.value

        XCTAssertEqual(interactor.uploadCallCount, 1)
        XCTAssertEqual(presenter.viewState.profileImageUpdateState, .success)
    }

    private func makeTestImage(size: CGSize) -> UIImage {
        UIGraphicsImageRenderer(size: size).image { context in
            UIColor.systemBlue.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            UIColor.white.setFill()
            context.cgContext.fillEllipse(in: CGRect(x: size.width * 0.2, y: size.height * 0.2, width: size.width * 0.6, height: size.height * 0.6))
        }
    }

    private func makeAuthenticatedSessionStore() -> SessionStore {
        let suiteName = "ProfileImageUpdateTests.\(UUID().uuidString)"
        let userDefaults = UserDefaults(suiteName: suiteName)!
        userDefaults.removePersistentDomain(forName: suiteName)
        let store = SessionStore(
            tokenStore: StubProfileTokenStore(),
            userDefaultsStore: UserDefaultsStore(userDefaults: userDefaults),
            sessionSnapshotStore: StubProfileSessionSnapshotStore()
        )
        store.apply(session: UserSession(
            userID: "user-1",
            email: "user@example.com",
            displayName: "픽코",
            profileImagePath: "https://example.com/old.jpg",
            accessToken: "access-token",
            refreshToken: "refresh-token"
        ))
        return store
    }
}

@MainActor
private final class StubProfileInteractor: ProfileInteracting {
    let uploadedPath = "https://example.com/new.jpg"
    var uploadError: Error?
    var holdInitialLoad = false
    var holdUpload = false
    private(set) var uploadCallCount = 0
    var profileRefetchPath: String?
    private var loadStarted = false
    private var loadStartedContinuation: CheckedContinuation<Void, Never>?
    private var loadReleaseContinuation: CheckedContinuation<Void, Never>?
    private var uploadStarted = false
    private var uploadStartedContinuation: CheckedContinuation<Void, Never>?
    private var uploadReleaseContinuation: CheckedContinuation<Void, Never>?

    func waitForLoadStarted() async {
        if loadStarted { return }
        await withCheckedContinuation { continuation in
            loadStartedContinuation = continuation
        }
    }

    func releaseInitialLoad() {
        loadReleaseContinuation?.resume()
        loadReleaseContinuation = nil
    }

    func waitForUploadStarted() async {
        if uploadStarted { return }
        await withCheckedContinuation { continuation in
            uploadStartedContinuation = continuation
        }
    }

    func releaseUpload() {
        uploadReleaseContinuation?.resume()
        uploadReleaseContinuation = nil
    }

    func loadInitialState() async -> ProfileViewState {
        loadStarted = true
        loadStartedContinuation?.resume()
        loadStartedContinuation = nil

        if holdInitialLoad {
            await withCheckedContinuation { continuation in
                loadReleaseContinuation = continuation
            }
        }

        return ProfileViewState(
            displayName: "픽코",
            email: "user@example.com",
            phoneNumber: "",
            profileImagePath: "https://example.com/old-from-load.jpg",
            editorNick: "픽코",
            editorProfileImagePath: "https://example.com/old-from-load.jpg"
        )
    }

    func fetchMyProfile() async throws -> UserProfile {
        UserProfile(
            userID: "user-1",
            email: "user@example.com",
            nick: "픽코",
            phoneNumber: nil,
            profileImagePath: profileRefetchPath ?? uploadedPath
        )
    }

    func updateProfile(nick: String, phoneNumber: String?) async throws -> UserProfile {
        UserProfile(userID: "user-1", email: "user@example.com", nick: nick, phoneNumber: phoneNumber, profileImagePath: "https://example.com/old-from-put.jpg")
    }

    func uploadProfileImage(data: Data, fileName: String, mimeType: String) async throws -> String {
        uploadCallCount += 1
        uploadStarted = true
        uploadStartedContinuation?.resume()
        uploadStartedContinuation = nil
        if holdUpload {
            await withCheckedContinuation { continuation in
                uploadReleaseContinuation = continuation
            }
        }
        if let uploadError {
            throw uploadError
        }
        XCTAssertEqual(mimeType, "image/jpeg")
        XCTAssertEqual((fileName as NSString).pathExtension, "jpg")
        return uploadedPath
    }

    func logout() async throws {}
}

@MainActor
private final class StubProfileRouter: ProfileRouting {
    func routeToLikedStores() {}
    func routeToMyPosts(userID: String) {}
    func routeToLikedPosts() {}
    func routeToMyReviews(userID: String) {}
    func clearPendingRoute() {}
}

private actor StubProfileImageLoader: AuthorizedImageLoading {
    private var removedPaths: [String] = []

    func imageData(for path: String) async throws -> Data { Data() }
    func cachedImageData(for path: String) async throws -> Data? { nil }
    func removeCachedImage(for path: String) async throws {
        removedPaths.append(path)
    }
    func removedPathsSnapshot() -> [String] {
        removedPaths
    }
}

private final class StubProfileAuthRemoteDataSource: AuthRemoteDataSourceProtocol, @unchecked Sendable {
    var uploadedFieldFileName: String?
    var uploadedMimeType: String?
    var updatedNick: String?
    var updatedPhoneNumber: String?

    func signIn(with credential: SocialLoginCredential, deviceToken: String?) async throws -> LoginResponseDTO {
        throw NetworkError.invalidRequest
    }

    func signIn(email: String, password: String, deviceToken: String?) async throws -> LoginResponseDTO {
        throw NetworkError.invalidRequest
    }

    func signUp(email: String, password: String, nick: String, phoneNumber: String?, deviceToken: String?) async throws -> LoginResponseDTO {
        throw NetworkError.invalidRequest
    }

    func validateEmailAvailability(email: String) async throws {}

    func fetchMyProfile() async throws -> MyInfoResponseDTO {
        MyInfoResponseDTO(userID: "user-1", email: "user@example.com", nick: "픽코", profileImage: "/data/profiles/uploaded.jpg", phoneNum: "01012345678")
    }

    func updateMyProfile(nick: String, phoneNumber: String?) async throws -> MyInfoResponseDTO {
        updatedNick = nick
        updatedPhoneNumber = phoneNumber
        return MyInfoResponseDTO(userID: "user-1", email: "user@example.com", nick: nick, profileImage: "/data/profiles/current.jpg", phoneNum: phoneNumber)
    }

    func uploadProfileImage(data: Data, fileName: String, mimeType: String) async throws -> ProfileImageUploadResponseDTO {
        uploadedFieldFileName = fileName
        uploadedMimeType = mimeType
        return ProfileImageUploadResponseDTO(profileImage: "/data/profiles/uploaded.jpg")
    }

    func updateDeviceToken(_ deviceToken: String) async throws {}
    func searchUsers(nick: String?) async throws -> UserInfoListResponseDTO { UserInfoListResponseDTO(data: []) }
    func logout() async throws {}
}

private actor StubProfileTokenStore: TokenStore {
    func loadTokens() async throws -> StoredTokens? { nil }
    func saveTokens(_ tokens: StoredTokens) async throws {}
    func clearTokens() async throws {}
}

private actor StubProfileSessionSnapshotStore: SessionSnapshotStoring {
    func loadSnapshot() async -> StoredSessionProfile? { nil }
    func saveSnapshot(_ snapshot: StoredSessionProfile?) async throws {}
}

private struct StubProfileFileURLResolver: AuthorizedFileURLResolving {
    func resolveURL(from path: String) throws -> URL {
        URL(string: "https://example.com\(path)")!
    }

    func resolveOptionalURL(from path: String?) throws -> URL? {
        guard let path else { return nil }
        return try resolveURL(from: path)
    }
}
