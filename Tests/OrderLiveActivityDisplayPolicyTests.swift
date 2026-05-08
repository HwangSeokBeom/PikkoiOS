import XCTest
@testable import Pikko

final class OrderLiveActivityDisplayPolicyTests: XCTestCase {
    func testStatusDisplayUsesCompactKoreanLabelsAndProgress() {
        let cases: [(status: String, badge: String, compact: String, message: String, progress: Double)] = [
            ("PENDING_APPROVAL", "대기", "대기", "주문 확인 중", 0.2),
            ("APPROVED", "승인", "승인", "주문이 승인됐어요", 0.4),
            ("IN_PROGRESS", "조리", "조리", "메뉴 준비 중", 0.65),
            ("READY_FOR_PICKUP", "픽업", "픽업", "픽업할 수 있어요", 0.85),
            ("PICKED_UP", "완료", "완료", "픽업 완료", 1.0),
            ("CANCELLED", "취소", "취소", "주문 취소", 0.0)
        ]

        for item in cases {
            let display = OrderLiveActivityStatusDisplay.map(status: item.status)

            XCTAssertEqual(display.badge, item.badge)
            XCTAssertEqual(display.compact, item.compact)
            XCTAssertEqual(display.message, item.message)
            XCTAssertEqual(display.progress, item.progress, accuracy: 0.001)
        }
    }

    func testOrderCodePolicyShortensByMode() {
        XCTAssertEqual(
            OrderLiveActivityTextPolicy.displayOrderCode("RBUR-2026-00005644", mode: .short).text,
            "#5644"
        )
        XCTAssertEqual(
            OrderLiveActivityTextPolicy.displayOrderCode("RBUR-2026-00005644", mode: .medium).text,
            "Order RBUR...5644"
        )
    }

    func testTitlePolicyNormalizesAndPretruncatesLongTitles() {
        let title = OrderLiveActivityTextPolicy.displayTitle("  아주 긴 매장 이름과 대표 메뉴 이름이 함께 들어오는 주문  ", maxLength: 12)

        XCTAssertEqual(title.count, 12)
        XCTAssertTrue(title.hasSuffix("..."))
    }
}
