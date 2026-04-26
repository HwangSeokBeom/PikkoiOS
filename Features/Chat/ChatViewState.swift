import Foundation

struct ChatViewState: Equatable {
    var storeID: String?
    var title = "채팅"
    var subtitle = "가게 문의와 실시간 대화 기능은 이 루트에서 확장됩니다."
    var primaryActionTitle = "채팅 기능 준비 상태 보기"

    init(storeID: String? = nil) {
        self.storeID = storeID

        if let storeID, !storeID.isEmpty {
            subtitle = "가게 문의 채널을 준비 중이에요. storeID: \(storeID)"
        }
    }
}
