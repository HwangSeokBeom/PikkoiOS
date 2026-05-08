import CoreLocation
import Foundation

@MainActor
protocol StoreDetailInteracting {
    func loadInitialContent() async throws -> StoreDetailContent
    func updateLikeStatus(isLiked: Bool) async throws -> Bool
    func findReviewableOrderCode() async throws -> String?
    func deleteReview(reviewID: String) async throws
}

@MainActor
struct StoreDetailInteractor: StoreDetailInteracting {
    private let storeID: String
    private let source: String
    private let storeRepository: StoreRepository
    private let reviewRepository: ReviewRepository
    private let orderRepository: OrderRepository
    private let locationService: any LocationServiceProtocol

    init(
        storeID: String,
        storeRepository: StoreRepository,
        reviewRepository: ReviewRepository,
        orderRepository: OrderRepository,
        locationService: any LocationServiceProtocol
    ) {
        self.init(
            storeID: storeID,
            source: "unknown",
            storeRepository: storeRepository,
            reviewRepository: reviewRepository,
            orderRepository: orderRepository,
            locationService: locationService
        )
    }

    init(
        storeID: String,
        source: String = "unknown",
        storeRepository: StoreRepository,
        reviewRepository: ReviewRepository,
        orderRepository: OrderRepository,
        locationService: any LocationServiceProtocol
    ) {
        self.storeID = storeID
        self.source = source
        self.storeRepository = storeRepository
        self.reviewRepository = reviewRepository
        self.orderRepository = orderRepository
        self.locationService = locationService
    }

    func loadInitialContent() async throws -> StoreDetailContent {
        Logger(category: "StoreDetail").debug("[StoreDetail] load requested storeId=\(storeID) source=\(source)")
        let detailResult: StoreDetail
        do {
            detailResult = try await storeRepository.fetchStoreDetail(storeID: storeID)
        } catch {
            throw mapBlockingError(error)
        }

        async let reviewPageResult = loadReviewPage()
        async let reviewRatingsResult = loadReviewRatings()
        async let reviewEligibilityResult = loadReviewEligibility()

        let reviewsResult = await reviewPageResult
        let ratingsResult = await reviewRatingsResult
        let eligibilityResult = await reviewEligibilityResult

        return StoreDetailContent(
            detail: detailResult,
            reviewPage: reviewsResult.page,
            reviewRatings: ratingsResult.ratings,
            reviewEligibility: eligibilityResult.eligibility,
            distanceMeters: makeDistanceMeters(from: detailResult),
            warningMessage: reviewsResult.warningMessage ?? ratingsResult.warningMessage ?? eligibilityResult.warningMessage
        )
    }

    func updateLikeStatus(isLiked: Bool) async throws -> Bool {
        do {
            return try await storeRepository.updateLikeStatus(storeID: storeID, isLiked: isLiked)
        } catch {
            throw mapBlockingError(error)
        }
    }

    func findReviewableOrderCode() async throws -> String? {
        do {
            let page = try await orderRepository.fetchOrders(cursor: nil, filter: nil)
            return reviewEligibility(from: page.items).orderCode
        } catch {
            throw mapReviewMutationError(error)
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

    private func loadReviewEligibility() async -> (eligibility: StoreReviewEligibility, warningMessage: String?) {
        do {
            let page = try await orderRepository.fetchOrders(cursor: nil, filter: nil)
            return (reviewEligibility(from: page.items), nil)
        } catch {
            Logger.shared.warning("StoreDetail review eligibility load failed: \(error.localizedDescription)")
            return (
                .unavailable,
                nil
            )
        }
    }

    private func reviewEligibility(from orders: [OrderSummary]) -> StoreReviewEligibility {
        let storeOrders = orders.filter { $0.storeID == storeID }
        for order in storeOrders {
            let alreadyReviewed = order.reviewID != nil
            let paymentState = order.paymentVerificationState ?? (order.isPaymentCompleted ? "verified" : "unchecked")
            let isWritable = order.status == .completed && !alreadyReviewed
            let reason: String
            if order.storeID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                reason = "missingStoreId"
            } else if order.status != .completed {
                reason = "notPickedUp"
            } else if alreadyReviewed {
                reason = "alreadyReviewed"
            } else {
                reason = "pickedUpAndNotReviewed"
            }
            Logger.shared.debug(
                "[ReviewEligibility] orderCode=\(order.orderCode) storeId=\(order.storeID.isEmpty ? "nil" : order.storeID) status=\(order.status.apiValue) paymentState=\(paymentState) alreadyReviewed=\(alreadyReviewed) matchedReviewId=\(order.reviewID ?? "nil") isWritable=\(isWritable) reason=\(reason)"
            )
            if isWritable {
                return StoreReviewEligibility(orderCode: order.orderCode, disabledReasonText: nil)
            }
        }

        let disabledReason = storeOrders.contains(where: { $0.status == .completed && $0.reviewID != nil })
            ? "이미 이 주문에 대한 리뷰를 작성했어요."
            : "픽업 완료된 주문 내역에서 리뷰를 작성할 수 있어요."
        return StoreReviewEligibility(orderCode: nil, disabledReasonText: disabledReason)
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
        case .unauthorized, .authenticationFailed, .accessTokenExpired, .refreshTokenExpired, .configuration:
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
        case .unauthorized, .authenticationFailed, .accessTokenExpired, .refreshTokenExpired, .configuration:
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
