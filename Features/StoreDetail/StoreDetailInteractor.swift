import CoreLocation
import Foundation

@MainActor
protocol StoreDetailInteracting {
    func loadInitialContent() async throws -> StoreDetailContent
    func updateLikeStatus(isLiked: Bool) async throws -> Bool
    func deleteReview(reviewID: String) async throws
}

@MainActor
struct StoreDetailInteractor: StoreDetailInteracting {
    private let storeID: String
    private let storeRepository: StoreRepository
    private let reviewRepository: ReviewRepository
    private let locationService: any LocationServiceProtocol

    init(
        storeID: String,
        storeRepository: StoreRepository,
        reviewRepository: ReviewRepository,
        locationService: any LocationServiceProtocol
    ) {
        self.storeID = storeID
        self.storeRepository = storeRepository
        self.reviewRepository = reviewRepository
        self.locationService = locationService
    }

    func loadInitialContent() async throws -> StoreDetailContent {
        let detailResult: StoreDetail
        do {
            detailResult = try await storeRepository.fetchStoreDetail(storeID: storeID)
        } catch {
            throw mapBlockingError(error)
        }

        async let reviewPageResult = loadReviewPage()
        async let reviewRatingsResult = loadReviewRatings()

        let reviewsResult = await reviewPageResult
        let ratingsResult = await reviewRatingsResult

        return StoreDetailContent(
            detail: detailResult,
            reviewPage: reviewsResult.page,
            reviewRatings: ratingsResult.ratings,
            distanceMeters: makeDistanceMeters(from: detailResult),
            warningMessage: reviewsResult.warningMessage ?? ratingsResult.warningMessage
        )
    }

    func updateLikeStatus(isLiked: Bool) async throws -> Bool {
        do {
            return try await storeRepository.updateLikeStatus(storeID: storeID, isLiked: isLiked)
        } catch {
            throw mapBlockingError(error)
        }
    }

    func deleteReview(reviewID: String) async throws {
        do {
            try await reviewRepository.deleteReview(storeID: storeID, reviewID: reviewID)
        } catch {
            throw mapReviewMutationError(error)
        }
    }

    private func makeDistanceMeters(from detail: StoreDetail) -> Double? {
        guard let currentLocation = locationService.currentLocation,
              let latitude = detail.latitude,
              let longitude = detail.longitude else {
            return nil
        }

        let storeLocation = CLLocation(latitude: latitude, longitude: longitude)
        return currentLocation.distance(from: storeLocation)
    }

    private func loadReviewPage() async -> (page: CursorPage<StoreReview>, warningMessage: String?) {
        do {
            let page = try await reviewRepository.fetchStoreReviews(
                storeID: storeID,
                nextCursor: nil,
                limit: 5,
                orderBy: .latest
            )
            return (page, nil)
        } catch {
            Logger.shared.warning("StoreDetail reviews load failed: \(error.localizedDescription)")
            return (
                CursorPage(items: [], nextCursor: nil),
                mapNonBlockingErrorMessage(error)
            )
        }
    }

    private func loadReviewRatings() async -> (ratings: [StoreReviewRatingBreakdown], warningMessage: String?) {
        do {
            let ratings = try await reviewRepository.fetchStoreReviewRatings(storeID: storeID)
            return (ratings, nil)
        } catch {
            Logger.shared.warning("StoreDetail review ratings load failed: \(error.localizedDescription)")
            return ([], mapNonBlockingErrorMessage(error))
        }
    }

    private func mapBlockingError(_ error: Error) -> StoreDetailFeatureError {
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
            return .unavailable(message: "가게 상세 요청 형식이 올바르지 않아요.")
        case .forbidden:
            return .unavailable(message: "가게 상세 접근 권한이 없어요.")
        case .notFound(let message),
             .conflict(let message),
             .businessAuthorization(let message),
             .server(let message):
            return .unavailable(message: message)
        case .rateLimited:
            return .unavailable(message: "요청이 너무 많아요. 잠시 후 다시 시도해 주세요.")
        case .decoding:
            return .unavailable(message: "가게 상세 응답을 해석하지 못했어요.")
        case .transport:
            return .unavailable(message: "네트워크 연결을 확인한 뒤 다시 시도해 주세요.")
        case .unauthorized, .accessTokenExpired, .refreshTokenExpired, .configuration:
            return .unavailable(message: networkError.localizedDescription)
        }
    }

    private func mapNonBlockingErrorMessage(_ error: Error) -> String {
        guard let networkError = error as? NetworkError else {
            return "리뷰 정보를 일부 불러오지 못했어요."
        }

        if networkError.isAuthenticationFailure {
            return "리뷰 정보는 로그인 후 확인할 수 있어요."
        }

        if networkError.isConfigurationFailure {
            return networkError.appConfigurationError?.userMessage ?? "앱 설정을 확인해 주세요."
        }

        switch networkError {
        case .transport:
            return "리뷰 정보를 일부 불러오지 못했어요. 네트워크 상태를 확인해 주세요."
        case .decoding:
            return "리뷰 정보를 일부 불러오지 못했어요."
        case .invalidRequest, .abnormalRequest, .forbidden, .rateLimited:
            return "리뷰 정보를 일부 불러오지 못했어요."
        case .notFound(let message),
             .conflict(let message),
             .businessAuthorization(let message),
             .server(let message):
            return message
        case .unauthorized, .accessTokenExpired, .refreshTokenExpired, .configuration:
            return networkError.localizedDescription
        }
    }

    private func mapReviewMutationError(_ error: Error) -> StoreDetailFeatureError {
        guard let networkError = error as? NetworkError else {
            return .unavailable(message: "리뷰를 삭제하지 못했어요.")
        }

        if networkError.isAuthenticationFailure {
            return .authenticationRequired
        }

        switch networkError {
        case .notFound:
            return .unavailable(message: "삭제되었거나 찾을 수 없는 리뷰입니다.")
        case .businessAuthorization, .forbidden:
            return .unavailable(message: "작성자만 수정/삭제할 수 있습니다.")
        case .transport:
            return .unavailable(message: "네트워크 연결을 확인한 뒤 다시 시도해 주세요.")
        case .abnormalRequest(let message),
             .conflict(let message),
             .server(let message):
            return .unavailable(message: message)
        default:
            return .unavailable(message: "리뷰를 삭제하지 못했어요.")
        }
    }
}
