import Foundation

enum AuthPresentationContext: Equatable, Sendable {
    case generic
    case checkout
    case orderHistory
    case communityCompose
    case communityComment
    case protectedResource

    var title: String {
        switch self {
        case .generic:
            return "서비스 이용을 위해 로그인이 필요합니다."
        default:
            return "로그인이 필요합니다."
        }
    }

    var subtitle: String {
        switch self {
        case .generic:
            return "로그인 후 Pikko의 픽업 주문 서비스를 이용할 수 있습니다."
        case .checkout:
            return "주문을 생성하고 결제를 이어가려면 로그인이 필요합니다."
        case .orderHistory:
            return "사용자별 주문 내역과 상세 정보는 로그인 후 확인할 수 있습니다."
        case .communityCompose:
            return "커뮤니티 글을 작성하려면 로그인이 필요합니다."
        case .communityComment:
            return "댓글을 작성하려면 로그인이 필요합니다."
        case .protectedResource:
            return "이 기능은 사용자 인증 후에만 이용할 수 있습니다."
        }
    }
}
