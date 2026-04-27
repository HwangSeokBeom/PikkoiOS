import CoreLocation
import Foundation

@MainActor
protocol CommunityComposerInteracting {
    func loadInitialContent() async throws -> CommunityComposerContent
    func uploadAttachments(_ files: [CommunityPostUploadFile]) async throws -> [String]
    func submitPost(draft: CommunityComposerDraft) async throws -> CommunityPostDetail
}

@MainActor
struct CommunityComposerInteractor: CommunityComposerInteracting {
    private let mode: CommunityComposerMode
    private let initialDraft: CommunityComposerDraft?
    private let communityRepository: CommunityRepository
    private let locationService: any LocationServiceProtocol

    init(
        mode: CommunityComposerMode = .create,
        initialDraft: CommunityComposerDraft? = nil,
        communityRepository: CommunityRepository,
        locationService: any LocationServiceProtocol
    ) {
        self.mode = mode
        self.initialDraft = initialDraft
        self.communityRepository = communityRepository
        self.locationService = locationService
    }

    func loadInitialContent() async throws -> CommunityComposerContent {
        switch mode {
        case .create:
            return .create(initialDraft: initialDraft ?? .empty)
        case .edit(let postID):
            if let initialDraft {
                return .edit(postID: postID, initialDraft: initialDraft)
            }

            let detail = try await loadDetailForEditing(postID: postID)
            return .edit(
                postID: postID,
                initialDraft: makeDraft(from: detail)
            )
        }
    }

    func uploadAttachments(_ files: [CommunityPostUploadFile]) async throws -> [String] {
        guard !files.isEmpty else {
            return []
        }

        do {
            return try await communityRepository.uploadPostFiles(files)
        } catch {
            throw mapUploadError(error)
        }
    }

    func submitPost(draft: CommunityComposerDraft) async throws -> CommunityPostDetail {
        let normalizedCategory = draft.categoryTitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let normalizedTitle = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedBody = draft.body.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !normalizedCategory.isEmpty else {
            throw CommunityComposerFeatureError.validation(message: "카테고리를 선택해 주세요.")
        }

        guard !normalizedTitle.isEmpty, !normalizedBody.isEmpty else {
            throw CommunityComposerFeatureError.validation(message: "제목과 본문을 모두 입력해 주세요.")
        }

        let resolvedCoordinates = try await resolveCoordinates(for: draft)
        let submission = CommunityPostDraftSubmission(
            category: normalizedCategory,
            title: normalizedTitle,
            content: normalizedBody,
            latitude: resolvedCoordinates.latitude,
            longitude: resolvedCoordinates.longitude,
            storeID: draft.store?.id,
            // 상세 응답은 절대 URL로 resolve될 수 있어 서버가 기대하는 상대경로로 다시 정규화한다.
            filePaths: normalizedAttachmentPaths(draft.attachments)
        )

        do {
            switch mode {
            case .create:
                return try await communityRepository.createPost(submission)
            case .edit(let postID):
                return try await communityRepository.updatePost(postID: postID, submission: submission)
            }
        } catch {
            #if DEBUG
            Logger.shared.debug(
                "[CommunityCreate] failed status=\(debugStatusDescription(from: error)) reason=\(error.localizedDescription)"
            )
            #endif
            throw mapSubmissionError(error)
        }
    }

    private func loadDetailForEditing(postID: String) async throws -> CommunityPostDetail {
        do {
            return try await communityRepository.fetchPostDetail(postID: postID)
        } catch {
            throw mapSubmissionError(error)
        }
    }

    private func makeDraft(from detail: CommunityPostDetail) -> CommunityComposerDraft {
        CommunityComposerDraft(
            title: detail.summary.title,
            body: detail.summary.content,
            categoryTitle: detail.summary.category,
            store: detail.summary.store.map {
                .init(id: $0.id, name: $0.name)
            },
            attachments: detail.summary.mediaPaths.map(makeRouteAttachment),
            latitude: detail.summary.latitude,
            longitude: detail.summary.longitude
        )
    }

    private func makeRouteAttachment(path: String) -> CommunityComposerRouteAttachment {
        CommunityComposerRouteAttachment(
            path: normalizeAttachmentPathForRequest(path)
        )
    }

    private func normalizedAttachmentPaths(
        _ attachments: [CommunityComposerRouteAttachment]
    ) -> [String] {
        attachments
            .map(\.path)
            .map(normalizeAttachmentPathForRequest)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    private func normalizeAttachmentPathForRequest(_ path: String) -> String {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return trimmed
        }

        if let absoluteURL = URL(string: trimmed),
           let scheme = absoluteURL.scheme,
           !scheme.isEmpty {
            let resolvedPath = absoluteURL.path
            if resolvedPath.hasPrefix("/v1/data/") {
                return String(resolvedPath.dropFirst(3))
            }
            return resolvedPath
        }

        if trimmed.hasPrefix("/v1/data/") {
            return String(trimmed.dropFirst(3))
        }

        return trimmed
    }

    private func resolveCoordinates(for draft: CommunityComposerDraft) async throws -> (latitude: Double, longitude: Double) {
        if let latitude = draft.latitude,
           let longitude = draft.longitude {
            return (latitude, longitude)
        }

        let location = try await resolveRequiredLocation()
        return (location.coordinate.latitude, location.coordinate.longitude)
    }

    private func resolveRequiredLocation() async throws -> CLLocation {
        if let selectedLocation = SelectedLocationStore.shared.selectedLocation {
            return CLLocation(
                latitude: selectedLocation.latitude,
                longitude: selectedLocation.longitude
            )
        }

        if let currentLocation = locationService.currentLocation {
            return currentLocation
        }

        do {
            return try await locationService.requestCurrentLocation()
        } catch LocationServiceError.authorizationNotDetermined {
            locationService.requestWhenInUseAuthorization()
            throw CommunityComposerFeatureError.validation(
                message: "게시글 작성을 위해 위치 권한을 허용한 뒤 다시 시도해 주세요."
            )
        } catch LocationServiceError.unauthorized, LocationServiceError.servicesDisabled {
            throw CommunityComposerFeatureError.validation(
                message: "게시글 작성을 위해 위치 권한이 필요해요."
            )
        } catch LocationServiceError.noLocationAvailable {
            throw CommunityComposerFeatureError.validation(
                message: "현재 위치를 확인한 뒤 다시 시도해 주세요."
            )
        } catch let error as CommunityComposerFeatureError {
            throw error
        } catch {
            Logger.shared.info("Community composer continuing without a resolved location.")
            throw CommunityComposerFeatureError.unavailable(
                message: "현재 위치를 확인하지 못했어요. 잠시 후 다시 시도해 주세요."
            )
        }
    }

    private func mapSubmissionError(_ error: Error) -> CommunityComposerFeatureError {
        guard let networkError = error as? NetworkError else {
            return .unavailable(message: error.localizedDescription)
        }

        if networkError.isAuthenticationFailure {
            return .authenticationRequired
        }

        if networkError.isConfigurationFailure {
            return .unavailable(
                message: networkError.appConfigurationError?.userMessage ?? "앱 설정을 확인해 주세요."
            )
        }

        switch networkError {
        case .invalidRequest, .abnormalRequest:
            return .validation(message: "입력값을 다시 확인해 주세요.")
        case .forbidden:
            switch mode {
            case .create:
                return .unavailable(message: "게시글 작성 권한이 없어요.")
            case .edit:
                return .unavailable(message: "게시글 수정 권한이 없어요.")
            }
        case .notFound(let message),
             .conflict(let message),
             .businessAuthorization(let message),
             .server(let message):
            return .unavailable(message: message)
        case .rateLimited:
            return .unavailable(message: "요청이 너무 많아요. 잠시 후 다시 시도해 주세요.")
        case .transport:
            return .unavailable(message: "네트워크 연결을 확인한 뒤 다시 시도해 주세요.")
        case .decoding:
            return .unavailable(message: "게시글 응답을 해석하지 못했어요.")
        case .unauthorized, .accessTokenExpired, .refreshTokenExpired, .configuration:
            return .unavailable(message: networkError.localizedDescription)
        }
    }

    private func mapUploadError(_ error: Error) -> CommunityComposerFeatureError {
        guard let networkError = error as? NetworkError else {
            return .unavailable(message: error.localizedDescription)
        }

        if networkError.isAuthenticationFailure {
            return .authenticationRequired
        }

        if networkError.isConfigurationFailure {
            return .unavailable(
                message: networkError.appConfigurationError?.userMessage ?? "앱 설정을 확인해 주세요."
            )
        }

        switch networkError {
        case .invalidRequest, .abnormalRequest:
            return .validation(message: "첨부 파일 형식과 용량을 다시 확인해 주세요.")
        case .forbidden:
            return .unavailable(message: "첨부 파일 업로드 권한이 없어요.")
        case .notFound(let message),
             .conflict(let message),
             .businessAuthorization(let message),
             .server(let message):
            return .unavailable(message: message)
        case .rateLimited:
            return .unavailable(message: "업로드 요청이 많아요. 잠시 후 다시 시도해 주세요.")
        case .transport:
            return .unavailable(message: "네트워크 연결을 확인한 뒤 다시 시도해 주세요.")
        case .decoding:
            return .unavailable(message: "첨부 파일 업로드 응답을 해석하지 못했어요.")
        case .unauthorized, .accessTokenExpired, .refreshTokenExpired, .configuration:
            return .unavailable(message: networkError.localizedDescription)
        }
    }

    private func debugStatusDescription(from error: Error) -> String {
        guard let networkError = error as? NetworkError else {
            return "unknown"
        }

        switch networkError {
        case .invalidRequest, .abnormalRequest:
            return "400/422"
        case .unauthorized:
            return "401"
        case .forbidden:
            return "403"
        case .notFound:
            return "404"
        case .conflict:
            return "409"
        case .refreshTokenExpired:
            return "418"
        case .accessTokenExpired:
            return "419"
        case .configuration:
            return "420"
        case .rateLimited:
            return "429"
        case .businessAuthorization:
            return "445"
        case .server:
            return "5xx"
        case .decoding:
            return "2xx-decoding"
        case .transport:
            return "transport"
        }
    }
}
