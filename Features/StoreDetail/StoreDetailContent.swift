import Foundation

struct StoreDetailContent {
    let detail: StoreDetail
    let reviewPage: CursorPage<StoreReview>
    let reviewRatings: [StoreReviewRatingBreakdown]
    let reviewEligibility: StoreReviewEligibility
    let distanceMeters: Double?
    let warningMessage: String?
}

struct StoreReviewEligibility: Equatable {
    let orderCode: String?
    let disabledReasonText: String?

    var isWritable: Bool {
        orderCode != nil
    }

    static let unavailable = StoreReviewEligibility(
        orderCode: nil,
        disabledReasonText: "픽업 완료된 주문 내역에서 리뷰를 작성할 수 있어요."
    )
}

enum StoreDetailFeatureError: Error, Equatable {
    case authenticationRequired
    case unavailable(message: String)
}

extension StoreDetailFeatureError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .authenticationRequired:
            return "로그인 후 가게 상세를 확인할 수 있어요."
        case .unavailable(let message):
            return message
        }
    }
}
