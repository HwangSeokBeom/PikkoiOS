import Foundation

enum ProfileStatusTone: Equatable {
    case success
    case warning
}

struct ProfileViewState: Equatable {
    var title = "마이"
    var displayName = "로그인 정보를 불러오는 중이에요."
    var email = ""
    var phoneNumber = ""
    var profileImagePath: String?
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
    var isUploadingProfileImage = false
    var isSavingProfile = false
    var profileImageUploadErrorMessage: String?
    var editorErrorMessage: String?
    var editorInfoMessage: String?
    var noticeMessage: String?
    var noticeTone: ProfileStatusTone?

    var saveProfileActionTitle: String {
        if isUploadingProfileImage {
            return "이미지 업로드 중..."
        }

        return isSavingProfile ? "저장 중..." : "저장하기"
    }

    var canSaveProfile: Bool {
        !editorNick.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !isUploadingProfileImage
            && !isSavingProfile
            && profileImageUploadErrorMessage == nil
            && editorErrorMessage == nil
    }
}
