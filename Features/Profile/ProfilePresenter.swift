import Foundation

@MainActor
final class ProfilePresenter: ObservableObject {
    @Published private(set) var viewState = ProfileViewState()

    private let interactor: ProfileInteracting
    private let router: ProfileRouting
    private let sessionStore: SessionStore
    private let imageLoader: any AuthorizedImageLoading
    private var hasLoaded = false
    private var profileStateGeneration = 0
    private var editorOriginalNick = ""
    private var editorOriginalPhoneNumber = ""

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
            let generation = profileStateGeneration
            let loadedState = await interactor.loadInitialState()
            guard generation == profileStateGeneration else {
                Logger(category: "ProfileImageUpload").debug("[ProfileImageUpload] stale profile response ignored generation=\(generation) current=\(profileStateGeneration)")
                return
            }
            viewState = loadedState
        case .editProfileTapped:
            presentEditor()
        case .profileEditorDismissed:
            dismissEditor()
        case .editorNickChanged(let nick):
            viewState.editorNick = nick
            viewState.editorErrorMessage = nil
            syncEditorDirtyState()
        case .editorPhoneNumberChanged(let phoneNumber):
            viewState.editorPhoneNumber = phoneNumber
            viewState.editorErrorMessage = nil
            syncEditorDirtyState()
        case .profileImageDataSelected(let data, let fileName):
            await stageProfileImage(data: data, fileName: fileName)
        case .profileImageSelectionFailed(let message):
            viewState.profileImageUploadErrorMessage = message
            viewState.profileImageUpdateState = .failure(message: message)
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
        viewState.draftNickname = viewState.displayName
        viewState.editorPhoneNumber = viewState.phoneNumber
        editorOriginalNick = viewState.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        editorOriginalPhoneNumber = viewState.phoneNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        let currentProfileImagePath = viewState.profileImagePath ?? sessionStore.profileImagePath
        viewState.profileImagePath = currentProfileImagePath
        viewState.editorProfileImagePath = currentProfileImagePath
        viewState.editorProfileImageCacheRevision = viewState.profileImageCacheRevision
        viewState.editorLocalProfileImageData = nil
        viewState.stagedProfileImage = nil
        viewState.pendingProfileImageUpload = nil
        viewState.stagedProfileImageFile = nil
        viewState.profileImageUpdateState = .idle
        viewState.isProfileEditorDirty = false
        viewState.isDirty = false
        viewState.isSaving = false
        viewState.saveError = nil
        viewState.isEditingProfile = true
#if DEBUG
        Logger(category: "ProfileEdit").debug("[ProfileEdit] appear mode=edit")
#endif
    }

    private func dismissEditor() {
        viewState.isEditingProfile = false
        viewState.isUploadingProfileImage = false
        viewState.isSavingProfile = false
        viewState.profileImageUploadErrorMessage = nil
        viewState.editorErrorMessage = nil
        viewState.editorInfoMessage = nil
        viewState.editorLocalProfileImageData = nil
        viewState.stagedProfileImage = nil
        viewState.pendingProfileImageUpload = nil
        viewState.stagedProfileImageFile = nil
        viewState.profileImageUpdateState = .idle
        viewState.isProfileEditorDirty = false
        viewState.isDirty = false
        viewState.isSaving = false
        viewState.saveError = nil
    }

    private func stageProfileImage(data: Data, fileName: String) async {
        guard sessionStore.isAuthenticated else { return }
        guard !viewState.isSavingProfile else { return }
        guard !data.isEmpty else {
            Logger(category: "ProfileImage").warning("[ProfileImage] stage skipped reason=processedDataEmpty")
            return
        }

        viewState.editorErrorMessage = nil
        viewState.editorInfoMessage = nil
        viewState.profileImageUploadErrorMessage = nil
        viewState.profileImageUpdateState = .processingImage

        do {
            let processed: ProfileImagePreprocessResult
            do {
#if DEBUG
                Logger(category: "ProfileImage").debug("[ProfileImage] preprocess start targetMaxBytes=\(ProfileImagePreprocessor.maxBytes) allowedExtensions=jpg,jpeg,png")
#endif
                processed = try await ProfileImagePreprocessor().processForProfileUpload(data: data, originalFileName: fileName)
#if DEBUG
                Logger(category: "ProfileImageNormalize").debug("[ProfileImageNormalize] originalUTI=\(processed.originalUTI) originalMime=\(processed.originalMimeType) originalByteSize=\(processed.originalBytes) originalPixelSize=\(Int(processed.originalPixelSize.width))x\(Int(processed.originalPixelSize.height)) orientation=\(processed.orientation)")
                Logger(category: "ProfileImageNormalize").debug("[ProfileImageNormalize] outputMime=\(processed.mimeType) outputExtension=\(processed.fileExtension) outputByteSize=\(processed.data.count) outputPixelSize=\(Int(processed.pixelSize.width))x\(Int(processed.pixelSize.height)) compressionQuality=\(String(format: "%.2f", processed.compressionQuality)) downsampled=\(processed.didDownsample)")
                Logger(category: "ProfileImage").debug("[ProfileImage] normalized outputType=\(profileImageOutputType(mimeType: processed.mimeType)) outputBytes=\(processed.data.count) maxBytes=\(ProfileImagePreprocessor.maxBytes) compression=\(String(format: "%.2f", processed.compressionQuality))")
                Logger(category: "ProfileImage").debug("[ProfileImage] preprocess success outputType=\(profileImageOutputType(mimeType: processed.mimeType)) outputBytes=\(processed.data.count) compression=\(String(format: "%.2f", processed.compressionQuality)) maxPixel=\(Int(max(processed.pixelSize.width, processed.pixelSize.height)))")
#endif
            } catch {
#if DEBUG
                Logger(category: "ProfileImage").warning("[ProfileImage] preprocess failed reason=\(profileImageFailureClassification(from: error))")
#endif
                throw error
            }

            guard !processed.data.isEmpty else {
                Logger(category: "ProfileImage").warning("[ProfileImage] upload skipped reason=processedDataEmpty")
                throw ProfileImagePreprocessorError.decodeFailed
            }

            guard processed.data.count <= ProfileImagePreprocessor.maxBytes else {
                Logger(category: "ProfileImage").warning("[ProfileImage] upload skipped reason=fileTooLarge bytes=\(processed.data.count) limit=\(ProfileImagePreprocessor.maxBytes)")
                throw ProfileImagePreprocessorError.fileTooLargeAfterCompression
            }

#if DEBUG
            Logger(category: "ProfileImage").debug("[ProfileImage] staged preview fileName=\(processed.fileName) mime=\(processed.mimeType) bytes=\(processed.data.count)")
#endif
            profileStateGeneration += 1
            viewState.isEditingProfile = true
            viewState.editorLocalProfileImageData = processed.data
            viewState.stagedProfileImage = processed.data
            viewState.pendingProfileImageUpload = ProfilePendingImageUpload(
                data: processed.data,
                fileName: processed.fileName,
                mimeType: processed.mimeType
            )
            viewState.stagedProfileImageFile = viewState.pendingProfileImageUpload
            viewState.profileImageUpdateState = .idle
            syncEditorDirtyState()
#if DEBUG
            Logger(category: "ProfileEdit").debug("[ProfileEdit] stayOnEditAfterPicker selected=true routeStillEdit=\(viewState.isEditingProfile)")
#endif
        } catch {
            let message = resolveProfileImageUploadMessage(from: error)
            viewState.profileImageUploadErrorMessage = message
            viewState.profileImageUpdateState = .failure(message: message)
            viewState.pendingProfileImageUpload = nil
            viewState.stagedProfileImageFile = nil
#if DEBUG
            Logger(category: "ProfileImageUpload").warning("[ProfileImageUpload] failed stage=preprocess status=\(statusCodeDescription(from: error)) reason=\(error.localizedDescription)")
            Logger(category: "ProfileImage").warning("[ProfileImage] upload failed reason=\(profileImageFailureClassification(from: error)) status=\(statusCodeDescription(from: error)) isATS=\(isATSBlocked(error)) isValidation=\(isProfileImageValidationFailure(error))")
#endif
        }
    }

    private func uploadStagedProfileImageIfNeeded() async throws -> String? {
        guard let pendingUpload = viewState.pendingProfileImageUpload else {
            return nil
        }

        let requestID = UUID().uuidString
        let oldProfileImagePath = viewState.editorProfileImagePath ?? viewState.profileImagePath
        viewState.profileImageUpdateState = .uploadingImage(progress: nil)
        viewState.isUploadingProfileImage = true
        defer { viewState.isUploadingProfileImage = false }

        #if DEBUG
        Logger(category: "ProfileImage").debug("[ProfileImage] upload start endpoint=/v1/users/profile/image fieldName=profile fileName=\(pendingUpload.fileName) mime=\(pendingUpload.mimeType) bytes=\(pendingUpload.data.count)")
        #endif

        let uploadedPath = try await interactor.uploadProfileImage(
            data: pendingUpload.data,
            fileName: pendingUpload.fileName,
            mimeType: pendingUpload.mimeType
        )

        #if DEBUG
        Logger(category: "ProfileImageUpdate").debug("[ProfileImageUpdate] uploadStatus=200 responseImageURL=\(uploadedPath)")
        Logger(category: "ProfileImageUpload").info("[ProfileImageUpload] success requestID=\(requestID) imageURLChanged=\(uploadedPath != oldProfileImagePath)")
        Logger(category: "ProfileImage").debug("[ProfileImage] upload success profileImage=\(uploadedPath)")
        #endif
        return uploadedPath
    }

    private func confirmProfileImageUpload(newPath: String, oldPath: String?) async {
        profileStateGeneration += 1
        await invalidateProfileImageCache(oldPath: oldPath, newPath: newPath)
        let oldConfirmedProfileImagePath = viewState.profileImagePath
        sessionStore.updateProfile(
            nick: sessionStore.currentSession?.displayName ?? viewState.displayName,
            profileImagePath: newPath
        )
        Logger(category: "ProfileState").debug("[ProfileState] imageURLUpdated userId=\(sessionStore.currentUserID ?? "unknown") imageURL=\(newPath)")
        Logger(category: "ProfileImage").debug("[ProfileImage] currentUser updated oldProfileImageExists=\(oldConfirmedProfileImagePath?.isEmpty == false) newProfileImageExists=\(!newPath.isEmpty)")
        Logger(category: "ProfileImage").debug("[ProfileImage] state update oldProfileImage=\(oldConfirmedProfileImagePath ?? "nil") newProfileImage=\(newPath)")
        viewState.profileImagePath = newPath
        viewState.profileImageCacheRevision += 1
        viewState.editorProfileImagePath = newPath
        viewState.editorProfileImageCacheRevision = viewState.profileImageCacheRevision
        viewState.editorLocalProfileImageData = nil
        viewState.pendingProfileImageUpload = nil
        viewState.profileImageUploadErrorMessage = nil
        viewState.profileImageUpdateState = .success

        do {
#if DEBUG
            Logger(category: "ProfileImage").debug("[ProfileImage] refresh profile after upload start")
#endif
            let confirmedProfile = try await interactor.fetchMyProfile()
            let confirmedPath = confirmedProfile.profileImagePath?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            let ignoredAsStale = confirmedPath != nil && confirmedPath != newPath
#if DEBUG
            Logger(category: "ProfileImageRefetch").debug("[ProfileImageRefetch] uncached=true status=success returnedProfileImage=\(confirmedPath ?? "nil") ignoredAsStale=\(ignoredAsStale)")
            Logger(category: "ProfileImage").debug("[ProfileImage] refresh profile after upload success profileImage=\(confirmedPath ?? "nil")")
#endif
            viewState.displayName = confirmedProfile.nick
            viewState.email = confirmedProfile.email
            viewState.phoneNumber = confirmedProfile.phoneNumber ?? ""
            viewState.serverProfile = confirmedProfile
            sessionStore.updateProfile(
                nick: confirmedProfile.nick,
                profileImagePath: newPath
            )
            if !ignoredAsStale {
                viewState.profileImagePath = newPath
                viewState.editorProfileImagePath = newPath
            }
        } catch {
#if DEBUG
            Logger(category: "ProfileImageRefetch").warning("[ProfileImageRefetch] uncached=true status=\(statusCodeDescription(from: error)) returnedProfileImage=nil ignoredAsStale=false")
            Logger(category: "ProfileImage").warning("[ProfileImage] refresh profile after upload failed reason=profileRefreshFailedAfterUpload status=\(statusCodeDescription(from: error))")
#endif
        }
    }

    private func saveProfile() async {
        guard sessionStore.isAuthenticated else { return }
#if DEBUG
        Logger(category: "ProfileEdit").debug("[ProfileEdit] save tapped dirty=\(viewState.isProfileEditorDirty) stagedImage=\(viewState.pendingProfileImageUpload != nil)")
#endif
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
        viewState.saveError = nil
        viewState.editorInfoMessage = nil
        viewState.isSavingProfile = true
        viewState.isSaving = true

        do {
            let normalizedNick = viewState.editorNick.trimmingCharacters(in: .whitespacesAndNewlines)
            let normalizedPhoneNumber = viewState.editorPhoneNumber.trimmingCharacters(in: .whitespacesAndNewlines)
            let textChanged = normalizedNick != editorOriginalNick || normalizedPhoneNumber != editorOriginalPhoneNumber
            let oldProfileImagePath = viewState.profileImagePath
            let uploadedProfileImagePath = try await uploadStagedProfileImageIfNeeded()
            let confirmedProfileImagePath: String?
            if textChanged {
#if DEBUG
                Logger(category: "ProfileImage").debug("[ProfileImage] profile update request path=/v1/users/me/profile profileImageIncluded=false")
#endif
                let profile = try await interactor.updateProfile(
                    nick: viewState.editorNick,
                    phoneNumber: viewState.editorPhoneNumber
                )
                confirmedProfileImagePath = uploadedProfileImagePath ?? oldProfileImagePath ?? profile.profileImagePath

                sessionStore.updateProfile(
                    nick: profile.nick,
                    profileImagePath: confirmedProfileImagePath
                )

                viewState.displayName = profile.nick
                viewState.email = profile.email
                viewState.phoneNumber = profile.phoneNumber ?? ""
                viewState.serverProfile = profile
                viewState.editorNick = profile.nick
                viewState.draftNickname = profile.nick
                viewState.editorPhoneNumber = profile.phoneNumber ?? ""
                editorOriginalNick = profile.nick.trimmingCharacters(in: .whitespacesAndNewlines)
                editorOriginalPhoneNumber = (profile.phoneNumber ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            } else {
                confirmedProfileImagePath = uploadedProfileImagePath ?? oldProfileImagePath
            }

            if let uploadedProfileImagePath {
                await confirmProfileImageUpload(newPath: uploadedProfileImagePath, oldPath: oldProfileImagePath)
            } else {
                viewState.profileImagePath = confirmedProfileImagePath
                viewState.editorProfileImagePath = confirmedProfileImagePath
            }
            viewState.editorProfileImageCacheRevision = viewState.profileImageCacheRevision
            viewState.editorLocalProfileImageData = nil
            viewState.stagedProfileImage = nil
            viewState.pendingProfileImageUpload = nil
            viewState.stagedProfileImageFile = nil
            viewState.profileImageUpdateState = .success
            viewState.profileImageUploadErrorMessage = nil
            viewState.editorErrorMessage = nil
            viewState.editorInfoMessage = nil
            viewState.isProfileEditorDirty = false
            viewState.isSavingProfile = false
            viewState.isDirty = false
            viewState.isSaving = false
            viewState.isEditingProfile = false
            viewState.noticeMessage = "프로필을 저장했어요."
            viewState.noticeTone = .success
#if DEBUG
            Logger(category: "ProfileEdit").debug("[ProfileEdit] save success profileImageURL=\(viewState.profileImagePath ?? "nil")")
#endif
        } catch {
            viewState.isSavingProfile = false
            viewState.isSaving = false
            let message = resolveEditorMessage(from: error, fallback: "프로필을 저장하지 못했어요.")
            viewState.editorErrorMessage = message
            viewState.saveError = message
            if viewState.pendingProfileImageUpload != nil {
                viewState.profileImageUploadErrorMessage = message
                viewState.profileImageUpdateState = .failure(message: message)
            }
#if DEBUG
            Logger(category: "ProfileEdit").warning("[ProfileEdit] save failed error=\(message)")
            Logger(category: "ProfileImage").warning("[ProfileImage] failed stage=profileUpdate status=\(statusCodeDescription(from: error)) message=\(error.localizedDescription)")
#endif
        }
    }

    private func syncEditorDirtyState() {
        let normalizedNick = viewState.editorNick.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedPhoneNumber = viewState.editorPhoneNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        viewState.isProfileEditorDirty = normalizedNick != editorOriginalNick
            || normalizedPhoneNumber != editorOriginalPhoneNumber
            || viewState.pendingProfileImageUpload != nil
        viewState.draftNickname = viewState.editorNick
        viewState.stagedProfileImage = viewState.editorLocalProfileImageData
        viewState.stagedProfileImageFile = viewState.pendingProfileImageUpload
        viewState.isDirty = viewState.isProfileEditorDirty
    }

    private func invalidateProfileImageCache(oldPath: String?, newPath: String?) async {
        let paths = [oldPath, newPath].compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        Logger(category: "ProfileImageCache").debug("[ProfileImageCache] invalidate oldURL=\(oldPath ?? "nil") newURL=\(newPath ?? "nil")")
        var cacheInvalidated = false
        for path in Set(paths) {
            do {
                try await imageLoader.removeCachedImage(for: path)
                cacheInvalidated = true
#if DEBUG
                Logger(category: "ProfileImage").debug("[ProfileImage] image cache invalidated oldURL=\(oldPath ?? "nil") newURL=\(newPath ?? "nil")")
#endif
            } catch {
#if DEBUG
                Logger(category: "ProfileImage").warning("[ProfileImage] failed stage=stateUpdate status=none message=\(error.localizedDescription)")
#endif
            }
        }
#if DEBUG
        Logger(category: "ProfileImageUpdate").debug("[ProfileImageUpdate] oldURL=\(oldPath ?? "nil") newURL=\(newPath ?? "nil") cacheInvalidated=\(cacheInvalidated) failedCacheInvalidated=\(cacheInvalidated) optimisticApplied=true")
#endif
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

    private func resolveProfileImageUploadMessage(from error: Error) -> String {
        if let preprocessingError = error as? ProfileImagePreprocessorError {
            return preprocessingError.localizedDescription
        }

        if let networkError = error as? NetworkError {
            switch networkError {
            case .invalidRequest, .abnormalRequest:
                return "업로드 가능한 이미지 형식과 용량을 확인해주세요."
            case .businessAuthorization(let message):
                Logger(category: "ProfileImage").warning("[ProfileImage] server validation failed status=400 message=\(message)")
                return "업로드 가능한 이미지 형식과 용량을 확인해주세요."
            case .decoding:
                return "프로필 이미지를 저장하지 못했어요. 네트워크 상태를 확인한 뒤 다시 시도해 주세요."
            default:
                return "프로필 이미지를 저장하지 못했어요. 네트워크 상태를 확인한 뒤 다시 시도해 주세요."
            }
        }

        return "이미지를 불러오지 못했어요. 다른 사진을 선택해 주세요."
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
        case .configuration(.atsBlocked):
            return "ATS"
        case .abnormalRequest, .businessAuthorization, .configuration, .transport, .decoding:
            return "unknown"
        }
    }

    private func profileImageOutputType(mimeType: String) -> String {
        switch mimeType.lowercased() {
        case "image/png":
            return "png"
        default:
            return "jpeg"
        }
    }

    private func profileImageFailureClassification(from error: Error) -> String {
        if let error = error as? ProfileImagePreprocessorError {
            switch error {
            case .unsupportedFormat:
                return "unsupportedFormat"
            case .decodeFailed:
                return "decodeFailed"
            case .compressionFailed:
                return "compressionFailed"
            case .fileTooLargeAfterCompression:
                return "fileTooLargeAfterCompression"
            }
        }

        if isATSBlocked(error) {
            return "atsBlocked"
        }

        guard let networkError = error as? NetworkError else {
            return "networkFailure"
        }

        switch networkError {
        case .unauthorized, .authenticationFailed, .accessTokenExpired, .refreshTokenExpired:
            return "unauthorized"
        case .invalidRequest, .abnormalRequest, .businessAuthorization:
            return "serverValidationFailed400"
        case .configuration(.atsBlocked):
            return "atsBlocked"
        default:
            return "networkFailure"
        }
    }

    private func isATSBlocked(_ error: Error) -> Bool {
        (error as? NetworkError) == .configuration(.atsBlocked)
    }

    private func isProfileImageValidationFailure(_ error: Error) -> Bool {
        if error is ProfileImagePreprocessorError {
            return true
        }
        guard let networkError = error as? NetworkError else {
            return false
        }
        switch networkError {
        case .invalidRequest, .abnormalRequest:
            return true
        default:
            return false
        }
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
