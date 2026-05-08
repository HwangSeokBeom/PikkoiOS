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
        case .editorPhoneNumberChanged(let phoneNumber):
            viewState.editorPhoneNumber = phoneNumber
            viewState.editorErrorMessage = nil
        case .profileImageDataSelected(let data, let fileName):
            await uploadProfileImage(data: data, fileName: fileName)
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
        viewState.editorPhoneNumber = viewState.phoneNumber
        editorOriginalNick = viewState.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        editorOriginalPhoneNumber = viewState.phoneNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        let currentProfileImagePath = viewState.profileImagePath ?? sessionStore.profileImagePath
        viewState.profileImagePath = currentProfileImagePath
        viewState.editorProfileImagePath = currentProfileImagePath
        viewState.editorProfileImageCacheRevision = viewState.profileImageCacheRevision
        viewState.editorLocalProfileImageData = nil
        viewState.profileImageUpdateState = .idle
        viewState.isEditingProfile = true
    }

    private func dismissEditor() {
        viewState.isEditingProfile = false
        viewState.isUploadingProfileImage = false
        viewState.isSavingProfile = false
        viewState.profileImageUploadErrorMessage = nil
        viewState.editorErrorMessage = nil
        viewState.editorInfoMessage = nil
        viewState.editorLocalProfileImageData = nil
        viewState.profileImageUpdateState = .idle
    }

    private func uploadProfileImage(data: Data, fileName: String) async {
        guard sessionStore.isAuthenticated else { return }
        guard !viewState.isUploadingProfileImage else { return }
        guard !data.isEmpty else {
            Logger(category: "ProfileImage").warning("[ProfileImage] upload skipped reason=processedDataEmpty")
            return
        }

        let requestID = UUID().uuidString
        let oldProfileImagePath = viewState.editorProfileImagePath ?? viewState.profileImagePath
        viewState.editorErrorMessage = nil
        viewState.editorInfoMessage = nil
        viewState.profileImageUploadErrorMessage = nil
        viewState.profileImageUpdateState = .processingImage
        viewState.isUploadingProfileImage = true

        do {
            let processed: ProfileImagePreprocessResult
            do {
#if DEBUG
                Logger(category: "ProfileImageNormalize").debug("[ProfileImageNormalize] selectedFilename=\(fileName) originalByteSize=\(data.count)")
#endif
                processed = try await ProfileImagePreprocessor().processForProfileUpload(data: data, originalFileName: fileName)
#if DEBUG
                Logger(category: "ProfileImageNormalize").debug("[ProfileImageNormalize] originalUTI=\(processed.originalUTI) originalMime=\(processed.originalMimeType) originalByteSize=\(processed.originalBytes) originalPixelSize=\(Int(processed.originalPixelSize.width))x\(Int(processed.originalPixelSize.height)) orientation=\(processed.orientation)")
                Logger(category: "ProfileImageNormalize").debug("[ProfileImageNormalize] outputMime=\(processed.mimeType) outputExtension=\(processed.fileExtension) outputByteSize=\(processed.data.count) outputPixelSize=\(Int(processed.pixelSize.width))x\(Int(processed.pixelSize.height)) compressionQuality=\(String(format: "%.2f", processed.compressionQuality)) downsampled=\(processed.didDownsample)")
#endif
            } catch {
#if DEBUG
                Logger(category: "ProfileImage").warning("[ProfileImage] upload failed status=none message=\(error.localizedDescription)")
#endif
                throw error
            }

            guard !processed.data.isEmpty else {
                Logger(category: "ProfileImage").warning("[ProfileImage] upload skipped reason=processedDataEmpty")
                throw ProfileImagePreprocessorError.invalidImage
            }

            guard processed.data.count <= ProfileImagePreprocessor.maxBytes else {
                Logger(category: "ProfileImage").warning("[ProfileImage] upload skipped reason=fileTooLarge bytes=\(processed.data.count) limit=\(ProfileImagePreprocessor.maxBytes)")
                throw ProfileImagePreprocessorError.exceedsLimit
            }

            viewState.editorLocalProfileImageData = processed.data
            viewState.profileImageUpdateState = .uploadingImage(progress: nil)
#if DEBUG
            Logger(category: "ProfileImageUpload").debug("[ProfileImageUpload] start requestID=\(requestID) byteSize=\(processed.data.count) mime=\(processed.mimeType)")
#endif
            let uploadedPath = try await interactor.uploadProfileImage(
                data: processed.data,
                fileName: processed.fileName,
                mimeType: processed.mimeType
            )
            let effectiveUploadedPath = uploadedPath
#if DEBUG
            Logger(category: "ProfileImageUpdate").debug("[ProfileImageUpdate] uploadStatus=200 responseImageURL=\(uploadedPath)")
            Logger(category: "ProfileImageUpload").info("[ProfileImageUpload] success requestID=\(requestID) imageURLChanged=\(effectiveUploadedPath != oldProfileImagePath)")
#endif
            profileStateGeneration += 1
            await invalidateProfileImageCache(oldPath: oldProfileImagePath, newPath: effectiveUploadedPath)
            let oldConfirmedProfileImagePath = viewState.profileImagePath
            sessionStore.updateProfile(
                nick: sessionStore.currentSession?.displayName ?? viewState.displayName,
                profileImagePath: effectiveUploadedPath
            )
            Logger(category: "ProfileState").debug("[ProfileState] imageURLUpdated userId=\(sessionStore.currentUserID ?? "unknown") imageURL=\(effectiveUploadedPath)")
            Logger(category: "ProfileImage").debug("[ProfileImage] currentUser updated oldProfileImageExists=\(oldConfirmedProfileImagePath?.isEmpty == false) newProfileImageExists=\(!effectiveUploadedPath.isEmpty)")
            viewState.profileImagePath = effectiveUploadedPath
            viewState.profileImageCacheRevision += 1
            viewState.editorProfileImagePath = effectiveUploadedPath
            viewState.editorProfileImageCacheRevision = viewState.profileImageCacheRevision
            viewState.editorLocalProfileImageData = nil
            viewState.profileImageUploadErrorMessage = nil
            viewState.editorInfoMessage = "프로필 이미지를 업로드했어요."
            viewState.profileImageUpdateState = .success

            do {
                let confirmedProfile = try await interactor.fetchMyProfile()
                let confirmedPath = confirmedProfile.profileImagePath?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
                let ignoredAsStale = confirmedPath != nil && confirmedPath != effectiveUploadedPath
#if DEBUG
                Logger(category: "ProfileImageRefetch").debug("[ProfileImageRefetch] uncached=true status=success returnedProfileImage=\(confirmedPath ?? "nil") ignoredAsStale=\(ignoredAsStale)")
#endif
                viewState.displayName = confirmedProfile.nick
                viewState.email = confirmedProfile.email
                viewState.phoneNumber = confirmedProfile.phoneNumber ?? ""
                sessionStore.updateProfile(
                    nick: confirmedProfile.nick,
                    profileImagePath: effectiveUploadedPath
                )
                if !ignoredAsStale {
                    viewState.profileImagePath = effectiveUploadedPath
                    viewState.editorProfileImagePath = effectiveUploadedPath
                }
            } catch {
#if DEBUG
                Logger(category: "ProfileImageRefetch").warning("[ProfileImageRefetch] uncached=true status=\(statusCodeDescription(from: error)) returnedProfileImage=nil ignoredAsStale=false")
#endif
            }
        } catch {
            let message = resolveProfileImageUploadMessage(from: error)
            viewState.profileImageUploadErrorMessage = message
            viewState.profileImageUpdateState = .failure(message: message)
            viewState.editorLocalProfileImageData = nil
#if DEBUG
            Logger(category: "ProfileImageUpload").warning("[ProfileImageUpload] failed requestID=\(requestID) status=\(statusCodeDescription(from: error)) reason=\(error.localizedDescription)")
            Logger(category: "ProfileImage").warning("[ProfileImage] upload failed status=\(statusCodeDescription(from: error)) message=\(error.localizedDescription)")
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
            let normalizedNick = viewState.editorNick.trimmingCharacters(in: .whitespacesAndNewlines)
            let normalizedPhoneNumber = viewState.editorPhoneNumber.trimmingCharacters(in: .whitespacesAndNewlines)
            let textChanged = normalizedNick != editorOriginalNick || normalizedPhoneNumber != editorOriginalPhoneNumber
            guard textChanged else {
                viewState.isSavingProfile = false
                viewState.isEditingProfile = false
                viewState.noticeMessage = "프로필을 저장했어요."
                viewState.noticeTone = .success
                return
            }
            let oldProfileImagePath = viewState.profileImagePath
#if DEBUG
            Logger(category: "ProfileImage").debug("[ProfileImage] profile update request path=/v1/users/me/profile profileImageIncluded=false")
#endif
            let profile = try await interactor.updateProfile(
                nick: viewState.editorNick,
                phoneNumber: viewState.editorPhoneNumber
            )
            let preservedProfileImagePath = oldProfileImagePath ?? profile.profileImagePath

            sessionStore.updateProfile(
                nick: profile.nick,
                profileImagePath: preservedProfileImagePath
            )

            viewState.displayName = profile.nick
            viewState.email = profile.email
            viewState.phoneNumber = profile.phoneNumber ?? ""
            viewState.profileImagePath = preservedProfileImagePath
            viewState.editorNick = profile.nick
            viewState.editorPhoneNumber = profile.phoneNumber ?? ""
            viewState.editorProfileImagePath = preservedProfileImagePath
            viewState.editorProfileImageCacheRevision = viewState.profileImageCacheRevision
            viewState.editorLocalProfileImageData = nil
            viewState.profileImageUpdateState = .success
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
        Logger(category: "ProfileImageCache").debug("[ProfileImageCache] invalidate oldURL=\(oldPath ?? "nil") newURL=\(newPath ?? "nil")")
        var cacheInvalidated = false
        for path in Set(paths) {
            do {
                try await imageLoader.removeCachedImage(for: path)
                cacheInvalidated = true
#if DEBUG
                Logger(category: "ProfileImage").debug("[ProfileImage] cache invalidated oldUrlExists=\(oldPath?.isEmpty == false) newUrlExists=\(newPath?.isEmpty == false)")
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
        if error is ProfileImagePreprocessorError {
            return error.localizedDescription
        }

        if let networkError = error as? NetworkError {
            switch networkError {
            case .invalidRequest, .abnormalRequest, .businessAuthorization:
                return "이미지 용량이 너무 커서 자동으로 줄였지만 업로드에 실패했어요. 다른 사진을 선택해 주세요."
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
        case .abnormalRequest, .businessAuthorization, .configuration, .transport, .decoding:
            return "unknown"
        }
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
