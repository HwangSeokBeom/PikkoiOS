import XCTest
@testable import Pikko

final class PushRouteParserTests: XCTestCase {
    func testChatPayloadCreatesChatRoute() {
        let result = NotificationRouteParser.parse(
            rawPayload: [
                "notificationType": "chat_message",
                "chatRoomId": "room-1",
                "storeId": "store-1",
                "title": "문의"
            ],
            source: .remoteFCM
        )

        XCTAssertEqual(result?.route, .chatRoom(roomId: "room-1", storeId: "store-1", title: "문의"))
    }

    func testCommunityCommentPayloadCreatesPostRouteWithComment() {
        let result = NotificationRouteParser.parse(
            rawPayload: [
                "type": "community_comment",
                "communityPostId": "post-1",
                "commentId": "comment-1"
            ],
            source: .remoteFCM
        )

        XCTAssertEqual(result?.route, .communityPost(postId: "post-1", commentId: "comment-1"))
    }

    func testCommunityLikePayloadCreatesPostRouteWithoutComment() {
        let result = NotificationRouteParser.parse(
            rawPayload: [
                "eventType": "like",
                "postId": "post-1"
            ],
            source: .remoteFCM
        )

        XCTAssertEqual(result?.route, .communityPost(postId: "post-1", commentId: nil))
    }

    func testOrderPayloadCreatesOrderDetailRoute() {
        let result = NotificationRouteParser.parse(
            rawPayload: [
                "type": "order_status",
                "orderCode": "order-1"
            ],
            source: .remoteFCM
        )

        XCTAssertEqual(result?.route, .orderDetail(orderCode: "order-1"))
    }

    func testMissingRequiredKeyReturnsNil() {
        let result = NotificationRouteParser.parse(
            rawPayload: ["type": "chat_message"],
            source: .remoteFCM
        )

        XCTAssertNil(result)
    }

    func testUnknownTypeFallsBackToNone() {
        let result = NotificationRouteParser.parse(
            rawPayload: ["type": "system"],
            source: .remoteFCM
        )

        XCTAssertEqual(result?.route, AppNotificationRoute.none)
    }

    func testLocalNotificationIsNotTreatedAsRemoteFCM() {
        let result = NotificationRouteParser.parse(
            rawPayload: [
                "type": "chat_message",
                "roomId": "room-1"
            ],
            source: .localNotification
        )

        XCTAssertNil(result)
    }
}
