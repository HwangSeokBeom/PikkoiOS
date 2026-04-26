import Foundation

struct StoreDetailContent {
    let detail: StoreDetail
    let reviewPage: CursorPage<StoreReview>
    let reviewRatings: [StoreReviewRatingBreakdown]
    let distanceMeters: Double?
    let warningMessage: String?
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
