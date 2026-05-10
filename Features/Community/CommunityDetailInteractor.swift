import CoreLocation
import Foundation

@MainActor
protocol CommunityDetailInteracting {
    func loadInitialContent() async throws -> CommunityDetailContent
    func deletePost() async throws
    func loadComments(nextCursor: String?) async throws -> CursorPage<CommunityComment>
    func createComment(content: String, parentCommentID: String?) async throws -> CommunityComment
    func updateComment(commentID: String, content: String) async throws -> CommunityComment
    func deleteComment(commentID: String) async throws
    func updateLikeStatus(isLiked: Bool) async throws -> Bool
}

@MainActor
struct CommunityDetailInteractor: CommunityDetailInteracting {
    private let postID: String
    private let communityRepository: CommunityRepository
    private let locationService: any LocationServiceProtocol
    private let sessionStore: SessionStore
    private let distanceCalculator = CommunityDistanceCalculator()

    init(
        postID: String,
        communityRepository: CommunityRepository,
        locationService: any LocationServiceProtocol,
        sessionStore: SessionStore
    ) {
        self.postID = postID
        self.communityRepository = communityRepository
        self.locationService = locationService
        self.sessionStore = sessionStore
    }

    func loadInitialContent() async throws -> CommunityDetailContent {
        let detail: CommunityPostDetail
        do {
            detail = try await communityRepository.fetchPostDetail(postID: postID)
        } catch {
            throw mapBlockingError(error)
        }

        return CommunityDetailContent(
            detail: applyCurrentUser(to: detail),
            distanceMeters: makeDistanceMeters(from: detail.summary)
        )
    }

    func deletePost() async throws {
        do {
            try await communityRepository.deletePost(postID: postID)
        } catch {
            throw mapPostMutationError(error)
        }
    }

    func loadComments(nextCursor: String?) async throws -> CursorPage<CommunityComment> {
        do {
            let page = try await communityRepository.fetchComments(
                postID: postID,
                nextCursor: nextCursor,
                limit: 20
            )
            return applyCurrentUser(to: page)
        } catch {
            throw mapCommentError(error)
        }
    }

    func createComment(content: String, parentCommentID: String?) async throws -> CommunityComment {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw CommunityDetailCommentFeatureError.validation(message: "댓글 내용을 입력해 주세요.")
        }

        do {
            let comment = try await communityRepository.createComment(
                postID: postID,
                content: trimmed,
                parentCommentID: parentCommentID
            )
            return applyCurrentUser(to: comment)
        } catch {
            throw mapCommentError(error)
        }
    }

    func updateComment(commentID: String, content: String) async throws -> CommunityComment {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw CommunityDetailCommentFeatureError.validation(message: "댓글 내용을 입력해 주세요.")
        }

        do {
            let comment = try await communityRepository.updateComment(
                postID: postID,
                commentID: commentID,
                content: trimmed
            )
            return applyCurrentUser(to: comment)
        } catch {
            throw mapCommentError(error)
        }
    }

    func deleteComment(commentID: String) async throws {
        do {
            try await communityRepository.deleteComment(
                postID: postID,
                commentID: commentID
            )
        } catch {
            throw mapCommentError(error)
        }
    }

    func updateLikeStatus(isLiked: Bool) async throws -> Bool {
        do {
            return try await communityRepository.updateLikeStatus(postID: postID, isLiked: isLiked)
        } catch {
            throw mapBlockingError(error)
        }
    }

    private func makeDistanceMeters(from summary: CommunityPostSummary) -> Double? {
        let referenceLocation: CommunityReferenceLocation?
        if let selectedLocation = SelectedLocationStore.shared.selectedLocation,
           distanceCalculator.isValidCoordinate(
               latitude: selectedLocation.latitude,
               longitude: selectedLocation.longitude
           ) {
            referenceLocation = CommunityReferenceLocation(
                longitude: selectedLocation.longitude,
                latitude: selectedLocation.latitude
            )
        } else if let currentLocation = locationService.currentLocation,
                  distanceCalculator.isValidCoordinate(
                      latitude: currentLocation.coordinate.latitude,
                      longitude: currentLocation.coordinate.longitude
                  ) {
            referenceLocation = CommunityReferenceLocation(
                longitude: currentLocation.coordinate.longitude,
                latitude: currentLocation.coordinate.latitude
            )
        } else {
            referenceLocation = nil
        }

        return distanceCalculator.distanceMeters(
            from: referenceLocation,
            toLongitude: summary.longitude,
            latitude: summary.latitude
        )
    }

    private func applyCurrentUser(to detail: CommunityPostDetail) -> CommunityPostDetail {
        CommunityPostDetail(
            summary: detail.summary,
            comments: applyCurrentUser(to: detail.comments)
        )
    }

    private func applyCurrentUser(to page: CursorPage<CommunityComment>) -> CursorPage<CommunityComment> {
        CursorPage(
            items: applyCurrentUser(to: page.items),
            nextCursor: page.nextCursor
        )
    }

    private func applyCurrentUser(to comments: [CommunityComment]) -> [CommunityComment] {
        let currentUserID = sessionStore.currentUserID
        return comments.map { applyCurrentUser(to: $0, currentUserID: currentUserID) }
    }

    private func applyCurrentUser(to comment: CommunityComment) -> CommunityComment {
        applyCurrentUser(to: comment, currentUserID: sessionStore.currentUserID)
    }

    private func applyCurrentUser(
        to comment: CommunityComment,
        currentUserID: String?
    ) -> CommunityComment {
        CommunityComment(
            id: comment.id,
            postID: comment.postID,
            parentCommentID: comment.parentCommentID,
            author: comment.author,
            content: comment.content,
            createdAt: comment.createdAt,
            updatedAt: comment.updatedAt,
            isMine: currentUserID == comment.author.id,
            isHidden: comment.isHidden,
            replies: comment.replies.map { applyCurrentUser(to: $0, currentUserID: currentUserID) }
        )
    }

    private func mapBlockingError(_ error: Error) -> CommunityDetailFeatureError {
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
            return .unavailable(message: "게시글 상세 요청 형식이 올바르지 않아요.")
        case .forbidden:
            return .unavailable(message: "게시글 상세 접근 권한이 없어요.")
        case .notFound(let message):
            return .notFound(message: message)
        case .conflict(let message),
             .businessAuthorization(let message),
             .server(let message):
            return .unavailable(message: message)
        case .rateLimited:
            return .unavailable(message: "요청이 너무 많아요. 잠시 후 다시 시도해 주세요.")
        case .decoding:
            return .unavailable(message: "게시글 상세 응답을 해석하지 못했어요.")
        case .transport:
            return .unavailable(message: "네트워크 연결을 확인한 뒤 다시 시도해 주세요.")
        case .unauthorized, .authenticationFailed, .accessTokenExpired, .refreshTokenExpired, .configuration:
            return .unavailable(message: networkError.localizedDescription)
        }
    }

    private func mapCommentError(_ error: Error) -> CommunityDetailCommentFeatureError {
        if let commentError = error as? CommunityDetailCommentFeatureError {
            return commentError
        }

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
            return .validation(message: "댓글 내용을 다시 확인해 주세요.")
        case .forbidden:
            return .forbidden(message: "작성자만 수정/삭제할 수 있습니다.")
        case .notFound(let message):
            return .notFound(message: message)
        case .businessAuthorization:
            return .forbidden(message: "작성자만 수정/삭제할 수 있습니다.")
        case .conflict(let message),
             .server(let message):
            return .unavailable(message: message)
        case .rateLimited:
            return .unavailable(message: "요청이 너무 많아요. 잠시 후 다시 시도해 주세요.")
        case .decoding:
            return .unavailable(message: "댓글 응답을 해석하지 못했어요.")
        case .transport:
            return .unavailable(message: "네트워크 연결을 확인한 뒤 다시 시도해 주세요.")
        case .unauthorized, .authenticationFailed, .accessTokenExpired, .refreshTokenExpired, .configuration:
            return .unavailable(message: networkError.localizedDescription)
        }
    }

    private func mapPostMutationError(_ error: Error) -> CommunityDetailFeatureError {
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
            return .unavailable(message: "게시글 요청 정보를 다시 확인해 주세요.")
        case .forbidden, .businessAuthorization:
            return .unavailable(message: "작성자만 수정/삭제할 수 있습니다.")
        case .notFound:
            return .notFound(message: "이미 삭제되었거나 찾을 수 없는 게시글입니다.")
        case .conflict(let message),
             .server(let message):
            return .unavailable(message: message)
        case .rateLimited:
            return .unavailable(message: "요청이 너무 많아요. 잠시 후 다시 시도해 주세요.")
        case .decoding:
            return .unavailable(message: "게시글 응답을 해석하지 못했어요.")
        case .transport:
            return .unavailable(message: "네트워크 연결을 확인한 뒤 다시 시도해 주세요.")
        case .unauthorized, .authenticationFailed, .accessTokenExpired, .refreshTokenExpired, .configuration:
            return .unavailable(message: networkError.localizedDescription)
        }
    }
}
