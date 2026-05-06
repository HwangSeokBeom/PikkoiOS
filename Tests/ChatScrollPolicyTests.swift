import XCTest
@testable import Pikko

final class ChatScrollPolicyTests: XCTestCase {
    func testSelfOptimisticAppendScrollsToBottom() {
        XCTAssertEqual(
            ChatScrollPolicy.action(for: .optimisticAppend),
            .scrollToBottom(reason: "optimistic")
        )
    }

    func testOtherMessageNearBottomScrollsToBottom() {
        XCTAssertEqual(
            ChatScrollPolicy.action(for: .messageReceived(senderIsCurrentUser: false, isNearBottom: true)),
            .scrollToBottom(reason: "nearBottom")
        )
    }

    func testOtherMessageAwayFromBottomShowsIndicator() {
        XCTAssertEqual(
            ChatScrollPolicy.action(for: .messageReceived(senderIsCurrentUser: false, isNearBottom: false)),
            .showNewMessageIndicator
        )
    }

    func testEchoReplaceKeepsPosition() {
        XCTAssertEqual(
            ChatScrollPolicy.action(for: .echoReplace(localTemporaryId: "local-1")),
            .keepPosition(reason: "echoReplace")
        )
    }

    func testPaginationPrependPreservesPosition() {
        XCTAssertEqual(
            ChatScrollPolicy.action(for: .paginationPrepend),
            .preservePosition
        )
    }

    func testDeepLinkInitialScrollUsesTargetMessageWhenAvailable() {
        XCTAssertEqual(
            ChatScrollPolicy.action(for: .initialLoad(targetMessageId: "message-1")),
            .scrollToMessage(id: "message-1", reason: "deepLink")
        )
    }

    func testDeepLinkInitialScrollFallsBackToLatest() {
        XCTAssertEqual(
            ChatScrollPolicy.action(for: .initialLoad(targetMessageId: nil)),
            .scrollToBottom(reason: "deepLink")
        )
    }
}
