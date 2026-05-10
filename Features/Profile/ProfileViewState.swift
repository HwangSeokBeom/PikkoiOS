import Foundation

enum ProfileStatusTone: Equatable {
    case success
    case warning
}

enum ProfileImageUpdateState: Equatable {
    case idle
    case picking
    case processingImage
    case uploadingImage(progress: Double?)
    case success
    case failure(message: String)
}

struct ProfilePendingImageUpload: Equatable {
    let data: Data
    let fileName: String
    let mimeType: String
}

struct ProfileViewState: Equatable {
    var serverProfile: UserProfile?
    var title = "마이"
    var displayName = "로그인 정보를 불러오는 중이에요."
    var email = ""
    var phoneNumber = ""
    var profileImagePath: String?
    var profileImageCacheRevision = 0
    var likedStoresActionTitle = "찜한 가게 보기"
    var myPostsActionTitle = "내 글 보기"
    var likedPostsActionTitle = "좋아요한 글 보기"
    var myReviewsActionTitle = "내 리뷰 보기"
    var editProfileActionTitle = "프로필 수정"
    var logoutActionTitle = "로그아웃"
    var isEditingProfile = false
    var editorTitle = "프로필 수정"
    var editorNick = ""
    var editorPhoneNumber = ""
    var editorProfileImagePath: String?
    var editorProfileImageCacheRevision = 0
    var editorLocalProfileImageData: Data?
    var pendingProfileImageUpload: ProfilePendingImageUpload?
    var profileImageUpdateState: ProfileImageUpdateState = .idle
    var isUploadingProfileImage = false
    var isSavingProfile = false
    var isProfileEditorDirty = false
    var profileImageUploadErrorMessage: String?
    var editorErrorMessage: String?
    var editorInfoMessage: String?
    var noticeMessage: String?
    var noticeTone: ProfileStatusTone?
    var draftNickname = ""
    var stagedProfileImage: Data?
    var stagedProfileImageFile: ProfilePendingImageUpload?
    var isDirty = false
    var isSaving = false
    var saveError: String?

    var profileImageDisplayPath: String? {
        cacheBusted(path: profileImagePath, revision: profileImageCacheRevision)
    }

    var editorProfileImageDisplayPath: String? {
        cacheBusted(path: editorProfileImagePath, revision: editorProfileImageCacheRevision)
    }

    var saveProfileActionTitle: String {
        return isSavingProfile ? "저장 중..." : "저장하기"
    }

    var canSaveProfile: Bool {
        !editorNick.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !isSavingProfile
            && isProfileEditorDirty
            && profileImageUploadErrorMessage == nil
            && editorErrorMessage == nil
    }

    private func cacheBusted(path: String?, revision: Int) -> String? {
        guard let trimmedPath = path?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmedPath.isEmpty else {
            return path
        }
        guard revision > 0 else { return trimmedPath }

        var components = URLComponents(string: trimmedPath)
        if components == nil, trimmedPath.hasPrefix("/") {
            components = URLComponents(string: "https://pikko.local\(trimmedPath)")
        }

        guard var components else {
            return trimmedPath
        }

        var queryItems = components.queryItems ?? []
        queryItems.removeAll { $0.name == "avatarRevision" }
        queryItems.append(URLQueryItem(name: "avatarRevision", value: "\(revision)"))
        components.queryItems = queryItems

        if trimmedPath.hasPrefix("/"),
           let path = components.url?.path {
            let query = components.percentEncodedQuery.map { "?\($0)" } ?? ""
            return "\(path)\(query)"
        }

        return components.string ?? trimmedPath
    }
}
