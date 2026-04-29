import CoreLocation
import XCTest
@testable import Pikko

@MainActor
final class StoreDetailInteractorTests: XCTestCase {
    func testLoadInitialContentKeepsDetailWhenReviewsFail() async throws {
        let interactor = StoreDetailInteractor(
            storeID: "store-1",
            storeRepository: StubStoreRepository(
                detailResult: .success(makeDetail())
            ),
            reviewRepository: StubReviewRepository(
                reviewsResult: .failure(NetworkError.transport),
                ratingsResult: .success([StoreReviewRatingBreakdown(rating: 5, count: 3)])
            ),
            orderRepository: StubOrderRepository(),
            locationService: StubLocationService()
        )

        let content = try await interactor.loadInitialContent()

        XCTAssertEqual(content.detail.id, "store-1")
        XCTAssertTrue(content.reviewPage.items.isEmpty)
        XCTAssertEqual(content.reviewRatings.count, 1)
        XCTAssertEqual(
            content.warningMessage,
            "리뷰 정보를 일부 불러오지 못했어요. 네트워크 상태를 확인해 주세요."
        )
    }

    func testLoadInitialContentMapsUnauthorizedDetailFailure() async {
        let interactor = StoreDetailInteractor(
            storeID: "store-1",
            storeRepository: StubStoreRepository(
                detailResult: .failure(NetworkError.unauthorized)
            ),
            reviewRepository: StubReviewRepository(),
            orderRepository: StubOrderRepository(),
            locationService: StubLocationService()
        )

        do {
            _ = try await interactor.loadInitialContent()
            XCTFail("Expected authenticationRequired error")
        } catch let error as StoreDetailFeatureError {
            XCTAssertEqual(error, .authenticationRequired)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    private func makeDetail() -> StoreDetail {
        StoreDetail(
            id: "store-1",
            category: "카페",
            name: "새싹 카페",
            description: "테스트 설명",
            hashTags: [],
            openTime: "09:00",
            closeTime: "21:00",
            address: "서울시 영등포구",
            estimatedPickupMinutes: 15,
            parkingGuide: "주차 가능",
            imagePaths: ["/v1/data/stores/store-1.jpg"],
            isPicchelin: true,
            isLiked: false,
            likeCount: 10,
            totalReviewCount: 3,
            totalOrderCount: 20,
            totalRating: 4.7,
            owner: nil,
            longitude: 126.9,
            latitude: 37.5,
            menus: [],
            createdAt: nil,
            updatedAt: nil
        )
    }
}

private struct StubStoreRepository: StoreRepository {
    var detailResult: Result<StoreDetail, Error> = .success(
        StoreDetail(
            id: "default-store",
            category: nil,
            name: "Default",
            description: nil,
            hashTags: [],
            openTime: nil,
            closeTime: nil,
            address: nil,
            estimatedPickupMinutes: nil,
            parkingGuide: nil,
            imagePaths: [],
            isPicchelin: false,
            isLiked: false,
            likeCount: 0,
            totalReviewCount: 0,
            totalOrderCount: 0,
            totalRating: nil,
            owner: nil,
            longitude: nil,
            latitude: nil,
            menus: [],
            createdAt: nil,
            updatedAt: nil
        )
    )
    var likeResult: Result<Bool, Error> = .success(false)

    func fetchStoreDetail(storeID: String) async throws -> StoreDetail {
        try detailResult.get()
    }

    func searchStores(name: String?) async throws -> [StoreSummary] {
        []
    }

    func fetchNearbyStores(
        category: String?,
        longitude: Double?,
        latitude: Double?,
        maxDistance: Double?,
        nextCursor: String?,
        limit: Int,
        orderBy: StoreSortOrder
    ) async throws -> CursorPage<StoreSummary> {
        CursorPage(items: [], nextCursor: nil)
    }

    func fetchPopularStores(category: String?) async throws -> [StoreSummary] {
        []
    }

    func fetchPopularSearchTerms() async throws -> [String] {
        []
    }

    func fetchLikedStores(
        category: String?,
        nextCursor: String?,
        limit: Int
    ) async throws -> CursorPage<StoreSummary> {
        CursorPage(items: [], nextCursor: nil)
    }

    func updateLikeStatus(storeID: String, isLiked: Bool) async throws -> Bool {
        try likeResult.get()
    }
}

private struct StubReviewRepository: ReviewRepository {
    var reviewsResult: Result<CursorPage<StoreReview>, Error> = .success(
        CursorPage(items: [], nextCursor: nil)
    )
    var ratingsResult: Result<[StoreReviewRatingBreakdown], Error> = .success([])

    func uploadReviewImages(
        storeID: String,
        files: [StoreReviewUploadFile]
    ) async throws -> [String] {
        []
    }

    func createReview(
        storeID: String,
        draft: StoreReviewDraft
    ) async throws -> UserStoreReview {
        throw NetworkError.invalidRequest
    }

    func fetchStoreReviews(
        storeID: String,
        nextCursor: String?,
        limit: Int,
        orderBy: StoreReviewSortOrder
    ) async throws -> CursorPage<StoreReview> {
        try reviewsResult.get()
    }

    func fetchReviewDetail(
        storeID: String,
        reviewID: String
    ) async throws -> UserStoreReview {
        throw NetworkError.notFound(message: "리뷰 정보를 찾을 수 없어요.")
    }

    func updateReview(
        storeID: String,
        reviewID: String,
        draft: StoreReviewDraft
    ) async throws -> UserStoreReview {
        throw NetworkError.invalidRequest
    }

    func deleteReview(
        storeID: String,
        reviewID: String
    ) async throws {}

    func fetchStoreReviewRatings(storeID: String) async throws -> [StoreReviewRatingBreakdown] {
        try ratingsResult.get()
    }

    func fetchUserReviews(
        userID: String,
        category: String?,
        nextCursor: String?,
        limit: Int
    ) async throws -> CursorPage<UserStoreReview> {
        CursorPage(items: [], nextCursor: nil)
    }
}

private struct StubOrderRepository: OrderRepository {
    var ordersResult: Result<CursorPage<OrderSummary>, Error> = .success(
        CursorPage(items: [], nextCursor: nil)
    )

    func fetchOrders(cursor: String?, filter: String?) async throws -> CursorPage<OrderSummary> {
        try ordersResult.get()
    }

    func fetchOrderDetail(orderID: String) async throws -> OrderDetail {
        throw NetworkError.notFound(message: "주문 정보를 찾을 수 없어요.")
    }

    func fetchPaymentReceipt(orderCode: String) async throws -> PaymentReceipt {
        PaymentReceipt(
            impUID: "imp_test",
            merchantUID: orderCode,
            amount: 12_000,
            currency: "KRW",
            status: "paid",
            methodText: "card",
            paidAt: Date(),
            receiptURL: nil
        )
    }

    func cancelOrder(orderCode: String) async throws -> OrderDetail {
        _ = orderCode
        throw NetworkError.invalidRequest
    }

    func updateOrderStatus(orderCode: String, status: OrderStatus) async throws {
        _ = orderCode
        _ = status
        throw NetworkError.invalidRequest
    }

    func validatePayment(_ request: PaymentValidationRequest) async throws -> ValidatedPaymentReceipt {
        _ = request
        throw NetworkError.invalidRequest
    }

    func validatePrice(_ request: CheckoutPriceValidationRequest) async throws -> CheckoutPriceValidationResult {
        .valid
    }

    func createOrder(_ submission: CheckoutOrderSubmission) async throws -> CreatedOrder {
        throw NetworkError.invalidRequest
    }
}

@MainActor
private final class StubLocationService: LocationServiceProtocol {
    var authorizationStatus: CLAuthorizationStatus = .authorizedWhenInUse
    var currentLocation: CLLocation?

    func requestWhenInUseAuthorization() {}

    func requestCurrentLocation() async throws -> CLLocation {
        if let currentLocation {
            return currentLocation
        }
        throw LocationServiceError.noLocationAvailable
    }

    func startUpdatingLocation() {}

    func stopUpdatingLocation() {}

    func locationUpdates() -> AsyncStream<CLLocation> {
        AsyncStream { continuation in
            continuation.finish()
        }
    }
}
