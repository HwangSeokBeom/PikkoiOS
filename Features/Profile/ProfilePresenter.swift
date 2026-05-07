import Foundation

@MainActor
final class ProfilePresenter: ObservableObject {
    @Published private(set) var viewState = ProfileViewState()

    private let interactor: ProfileInteracting
    private let router: ProfileRouting
    private let sessionStore: SessionStore
    private let imageLoader: any AuthorizedImageLoading
    private let imagePreprocessor = ProfileImagePreprocessor()
    private var hasLoaded = false

    init(
        interactor: ProfileInteracting,
        router: ProfileRouting,
        sessionStore: SessionStore,
        imageLoader: any AuthorizedImageLoading
    ) {
        self.interactor = interactor
        self.router = router
        self.sessionStore = sessionStore
        self.imageLoader = imageLoader
    }

    func send(_ action: ProfileAction) async {
        switch action {
        case .onAppear:
            guard !hasLoaded else { return }
            hasLoaded = true
            viewState = await interactor.loadInitialState()
        case .editProfileTapped:
            presentEditor()
        case .profileEditorDismissed:
            dismissEditor()
        case .editorNickChanged(let nick):
            viewState.editorNick = nick
            viewState.editorErrorMessage = nil
        case .editorPhoneNumberChanged(let phoneNumber):
            viewState.editorPhoneNumber = phoneNumber
            viewState.editorErrorMessage = nil
        case .profileImageDataSelected(let data, let fileName):
            await uploadProfileImage(data: data, fileName: fileName)
        case .saveProfileTapped:
            await saveProfile()
        case .likedStoresTapped:
            router.routeToLikedStores()
        case .myPostsTapped:
            routeToMyPosts()
        case .likedPostsTapped:
            router.routeToLikedPosts()
        case .myReviewsTapped:
            routeToMyReviews()
        case .logoutTapped:
            await handleLogout()
        }
    }

    private func handleLogout() async {
        guard sessionStore.isAuthenticated else { return }

        do {
            try await interactor.logout()
        } catch {
            Logger.shared.warning("Profile logout failed: \(error.localizedDescription)")
        }

        await sessionStore.clearSession()
        viewState = await interactor.loadInitialState()
    }

    private func presentEditor() {
        guard sessionStore.isAuthenticated else { return }

        viewState.noticeMessage = nil
        viewState.noticeTone = nil
        viewState.editorErrorMessage = nil
        viewState.editorInfoMessage = nil
        viewState.profileImageUploadErrorMessage = nil
        viewState.editorNick = viewState.displayName
        viewState.editorPhoneNumber = viewState.phoneNumber
        viewState.editorProfileImagePath = viewState.profileImagePath
        viewState.isEditingProfile = true
    }

    private func dismissEditor() {
        viewState.isEditingProfile = false
        viewState.isUploadingProfileImage = false
        viewState.isSavingProfile = false
        viewState.profileImageUploadErrorMessage = nil
        viewState.editorErrorMessage = nil
        viewState.editorInfoMessage = nil
    }

    private func uploadProfileImage(data: Data, fileName: String) async {
        guard sessionStore.isAuthenticated else { return }
        guard !viewState.isUploadingProfileImage, !data.isEmpty else { return }

        viewState.editorErrorMessage = nil
        viewState.editorInfoMessage = nil
        viewState.profileImageUploadErrorMessage = nil
        viewState.isUploadingProfileImage = true

        do {
            let processed: ProfileImagePreprocessResult
            do {
                processed = try imagePreprocessor.process(data: data, originalFileName: fileName)
#if DEBUG
                Logger(category: "ProfileImage").debug("[ProfileImage] resize result mimeType=\(processed.mimeType) bytes=\(processed.data.count) underLimit=\(processed.isUnderLimit)")
#endif
            } catch {
#if DEBUG
                Logger(category: "ProfileImage").warning("[ProfileImage] failed stage=resize status=none message=\(error.localizedDescription)")
#endif
                throw error
            }

#if DEBUG
            Logger(category: "ProfileImage").debug("[ProfileImage] upload request path=/v1/users/profile/image fieldName=profile bytes=\(processed.data.count)")
#endif
            let uploadedPath = try await interactor.uploadProfileImage(
                data: processed.data,
                fileName: processed.fileName,
                mimeType: processed.mimeType
            )
#if DEBUG
            Logger(category: "ProfileImage").debug("[ProfileImage] upload response profileImageExists=\(!uploadedPath.isEmpty)")
#endif
            viewState.editorProfileImagePath = uploadedPath
            viewState.profileImageUploadErrorMessage = nil
            viewState.editorInfoMessage = "프로필 이미지를 업로드했어요."
        } catch {
            viewState.profileImageUploadErrorMessage = resolveEditorMessage(from: error, fallback: "프로필 이미지를 업로드하지 못했어요.")
#if DEBUG
            Logger(category: "ProfileImage").warning("[ProfileImage] failed stage=upload status=\(statusCodeDescription(from: error)) message=\(error.localizedDescription)")
#endif
        }

        viewState.isUploadingProfileImage = false
    }

    private func saveProfile() async {
        guard sessionStore.isAuthenticated else { return }
        guard viewState.canSaveProfile else {
            if viewState.editorNick.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                viewState.editorErrorMessage = "닉네임을 입력해 주세요."
            } else if let uploadErrorMessage = viewState.profileImageUploadErrorMessage {
                viewState.editorErrorMessage = uploadErrorMessage
            } else if viewState.isUploadingProfileImage {
                viewState.editorErrorMessage = "이미지 업로드가 끝난 뒤 저장할 수 있어요."
            }
            return
        }

        viewState.editorErrorMessage = nil
        viewState.editorInfoMessage = nil
        viewState.isSavingProfile = true

        do {
            let oldProfileImagePath = viewState.profileImagePath
#if DEBUG
            Logger(category: "ProfileImage").debug("[ProfileImage] profile update request path=/v1/users/me/profile profileImageExists=\(viewState.editorProfileImagePath?.isEmpty == false)")
#endif
            let profile = try await interactor.updateProfile(
                nick: viewState.editorNick,
                phoneNumber: viewState.editorPhoneNumber,
                profileImagePath: viewState.editorProfileImagePath
            )

            sessionStore.updateProfile(
                nick: profile.nick,
                profileImagePath: profile.profileImagePath
            )
#if DEBUG
            Logger(category: "ProfileImage").debug("[ProfileImage] currentUser updated oldProfileImageExists=\(oldProfileImagePath?.isEmpty == false) newProfileImageExists=\(profile.profileImagePath?.isEmpty == false)")
#endif
            await invalidateProfileImageCache(oldPath: oldProfileImagePath, newPath: profile.profileImagePath)

            viewState.displayName = profile.nick
            viewState.email = profile.email
            viewState.phoneNumber = profile.phoneNumber ?? ""
            viewState.profileImagePath = profile.profileImagePath
            viewState.editorNick = profile.nick
            viewState.editorPhoneNumber = profile.phoneNumber ?? ""
            viewState.editorProfileImagePath = profile.profileImagePath
            viewState.profileImageUploadErrorMessage = nil
            viewState.editorErrorMessage = nil
            viewState.editorInfoMessage = nil
            viewState.isSavingProfile = false
            viewState.isEditingProfile = false
            viewState.noticeMessage = "프로필을 저장했어요."
            viewState.noticeTone = .success
        } catch {
            viewState.isSavingProfile = false
            viewState.editorErrorMessage = resolveEditorMessage(from: error, fallback: "프로필을 저장하지 못했어요.")
#if DEBUG
            Logger(category: "ProfileImage").warning("[ProfileImage] failed stage=profileUpdate status=\(statusCodeDescription(from: error)) message=\(error.localizedDescription)")
#endif
        }
    }

    private func invalidateProfileImageCache(oldPath: String?, newPath: String?) async {
        let paths = [oldPath, newPath].compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        for path in Set(paths) {
            do {
                try await imageLoader.removeCachedImage(for: path)
#if DEBUG
                Logger(category: "ProfileImage").debug("[ProfileImage] imageCache invalidated path=\(path)")
#endif
            } catch {
#if DEBUG
                Logger(category: "ProfileImage").warning("[ProfileImage] failed stage=stateUpdate status=none message=\(error.localizedDescription)")
#endif
            }
        }
    }

    private func routeToMyPosts() {
        guard let currentUserID = sessionStore.currentUserID,
              !currentUserID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            viewState.noticeMessage = "로그인 후 내 글을 확인할 수 있어요."
            viewState.noticeTone = .warning
            return
        }

        router.routeToMyPosts(userID: currentUserID)
    }

    private func routeToMyReviews() {
        guard let currentUserID = sessionStore.currentUserID,
              !currentUserID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            viewState.noticeMessage = "로그인 후 내 리뷰를 확인할 수 있어요."
            viewState.noticeTone = .warning
            return
        }

        router.routeToMyReviews(userID: currentUserID)
    }

    private func resolveEditorMessage(from error: Error, fallback: String) -> String {
        if let localizedError = error as? LocalizedError,
           let description = localizedError.errorDescription,
           !description.isEmpty {
            return description
        }

        if let networkError = error as? NetworkError {
            switch networkError {
            case .businessAuthorization(let message):
                return message
            case .configuration(let configurationError):
                return configurationError.userMessage
            case .transport:
                return "네트워크 상태를 확인해 주세요."
            case .invalidRequest:
                return "입력값을 다시 확인해 주세요."
            case .forbidden:
                return "프로필을 수정할 권한이 없어요."
            case .notFound(let message),
                 .conflict(let message),
                 .server(let message),
                 .abnormalRequest(let message):
                return message
            case .unauthorized, .authenticationFailed, .accessTokenExpired, .refreshTokenExpired:
                return "다시 로그인한 뒤 프로필을 수정해 주세요."
            case .rateLimited:
                return "요청이 많아요. 잠시 후 다시 시도해 주세요."
            case .decoding:
                return fallback
            }
        }

        return fallback
    }

    private func statusCodeDescription(from error: Error) -> String {
        guard let networkError = error as? NetworkError else {
            return "none"
        }

        switch networkError {
        case .invalidRequest:
            return "400"
        case .unauthorized, .authenticationFailed:
            return "401"
        case .forbidden:
            return "403"
        case .notFound:
            return "404"
        case .conflict:
            return "409"
        case .accessTokenExpired:
            return "419"
        case .refreshTokenExpired:
            return "418"
        case .rateLimited:
            return "429"
        case .server:
            return "5xx"
        case .abnormalRequest, .businessAuthorization, .configuration, .transport, .decoding:
            return "unknown"
        }
    }
}
