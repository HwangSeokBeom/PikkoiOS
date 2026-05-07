import XCTest
import UIKit
@testable import Pikko

@MainActor
final class ProfileImageUpdateTests: XCTestCase {
    func testProfileImagePreprocessorReturnsSupportedImageUnderOneMegabyte() throws {
        let image = makeTestImage(size: CGSize(width: 1600, height: 1600))
        let data = try XCTUnwrap(image.jpegData(compressionQuality: 1.0))

        let result = try ProfileImagePreprocessor().process(data: data, originalFileName: "avatar.png")

        XCTAssertLessThanOrEqual(result.data.count, ProfileImagePreprocessor.maxBytes)
        XCTAssertTrue(["image/jpeg", "image/png"].contains(result.mimeType))
        XCTAssertTrue(["jpg", "jpeg", "png"].contains((result.fileName as NSString).pathExtension))
    }

    func testUploadProfileImageReturnsServerPathWithoutResolvingToAbsoluteURL() async throws {
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

        XCTAssertEqual(path, "/data/profiles/uploaded.jpg")
        XCTAssertEqual(remote.uploadedFieldFileName, "profile.jpg")
        XCTAssertEqual(remote.uploadedMimeType, "image/jpeg")
    }

    func testUpdateProfileSendsUploadedProfileImagePath() async throws {
        let remote = StubProfileAuthRemoteDataSource()
        let repository = AuthRepositoryImpl(
            remoteDataSource: remote,
            tokenStore: StubProfileTokenStore(),
            sessionSnapshotStore: StubProfileSessionSnapshotStore(),
            fileURLResolver: StubProfileFileURLResolver()
        )

        _ = try await repository.updateMyProfile(
            nick: "픽코",
            phoneNumber: "01012345678",
            profileImagePath: "/data/profiles/uploaded.jpg"
        )

        XCTAssertEqual(remote.updatedProfileImagePath, "/data/profiles/uploaded.jpg")
    }

    private func makeTestImage(size: CGSize) -> UIImage {
        UIGraphicsImageRenderer(size: size).image { context in
            UIColor.systemBlue.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            UIColor.white.setFill()
            context.cgContext.fillEllipse(in: CGRect(x: size.width * 0.2, y: size.height * 0.2, width: size.width * 0.6, height: size.height * 0.6))
        }
    }
}

private final class StubProfileAuthRemoteDataSource: AuthRemoteDataSourceProtocol, @unchecked Sendable {
    var uploadedFieldFileName: String?
    var uploadedMimeType: String?
    var updatedProfileImagePath: String?

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

    func updateMyProfile(nick: String, phoneNumber: String?, profileImagePath: String?) async throws -> MyInfoResponseDTO {
        updatedProfileImagePath = profileImagePath
        return MyInfoResponseDTO(userID: "user-1", email: "user@example.com", nick: nick, profileImage: profileImagePath, phoneNum: phoneNumber)
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
