import XCTest
@testable import Pikko

final class PushRouteParserTests: XCTestCase {
    func testRoomIDPayloadCreatesChatRoute() {
        let result = NotificationRouteParser.parse(
            rawPayload: [
                "eventType": "chat_message",
                "room_id": "room-1"
            ],
            source: .remoteFCM
        )

        XCTAssertEqual(result?.route, .chatRoom(roomId: "room-1", storeId: nil, title: nil))
    }

    func testUnknownTypeWithRoomIDCreatesChatRoute() {
        let result = NotificationRouteParser.parse(
            rawPayload: [
                "type": "unknown",
                "room_id": "room-1"
            ],
            source: .remoteFCM
        )

        XCTAssertEqual(result?.route, .chatRoom(roomId: "room-1", storeId: nil, title: nil))
    }

    func testRoomIdPayloadCreatesChatRoute() {
        let result = NotificationRouteParser.parse(
            rawPayload: [
                "type": "chat",
                "roomId": "room-1"
            ],
            source: .remoteFCM
        )

        XCTAssertEqual(result?.route, .chatRoom(roomId: "room-1", storeId: nil, title: nil))
    }

    func testServerRoomIdAliasCreatesChatRoute() {
        let result = NotificationRouteParser.parse(
            rawPayload: [
                "pushType": "chat",
                "serverRoomId": "room-1"
            ],
            source: .remoteFCM
        )

        XCTAssertEqual(result?.route, .chatRoom(roomId: "room-1", storeId: nil, title: nil))
    }

    func testChatRoomIdPayloadCreatesChatRoute() {
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

    func testPostIDAndCommentIDPayloadCreatesPostRouteWithComment() {
        let result = NotificationRouteParser.parse(
            rawPayload: [
                "eventType": "post_comment",
                "post_id": "post-1",
                "comment_id": "comment-1"
            ],
            source: .remoteFCM
        )

        XCTAssertEqual(result?.route, .communityPost(postId: "post-1", commentId: "comment-1"))
    }

    func testPostIdAndCommentIdPayloadCreatesPostRouteWithComment() {
        let result = NotificationRouteParser.parse(
            rawPayload: [
                "type": "community_comment",
                "postId": "post-1",
                "commentId": "comment-1"
            ],
            source: .remoteFCM
        )

        XCTAssertEqual(result?.route, .communityPost(postId: "post-1", commentId: "comment-1"))
    }

    func testCommunityPostIdLikePayloadCreatesPostRouteWithoutComment() {
        let result = NotificationRouteParser.parse(
            rawPayload: [
                "eventType": "community_like",
                "communityPostId": "post-1"
            ],
            source: .remoteFCM
        )

        XCTAssertEqual(result?.route, .communityPost(postId: "post-1", commentId: nil))
    }

    func testPostIDOnlyPayloadCreatesPostRouteWithoutComment() {
        let result = NotificationRouteParser.parse(
            rawPayload: [
                "eventType": "post_like",
                "post_id": "post-1"
            ],
            source: .remoteFCM
        )

        XCTAssertEqual(result?.route, .communityPost(postId: "post-1", commentId: nil))
    }

    func testOrderCodeSnakePayloadCreatesOrderDetailRoute() {
        let result = NotificationRouteParser.parse(
            rawPayload: [
                "eventType": "order_status_changed",
                "order_code": "order-1"
            ],
            source: .remoteFCM
        )

        XCTAssertEqual(result?.route, .orderDetail(orderCode: "order-1"))
    }

    func testOrderCodeCamelPayloadCreatesOrderDetailRoute() {
        let result = NotificationRouteParser.parse(
            rawPayload: [
                "type": "order_status",
                "orderCode": "order-1"
            ],
            source: .remoteFCM
        )

        XCTAssertEqual(result?.route, .orderDetail(orderCode: "order-1"))
    }

    func testOrderIdPayloadCreatesOrderRouteByListLookupIdentifier() {
        let result = NotificationRouteParser.parse(
            rawPayload: [
                "notificationType": "order",
                "order_id": "order-id-1"
            ],
            source: .remoteFCM
        )

        XCTAssertEqual(result?.route, .orderDetail(orderCode: "order-id-1"))
    }

    func testMissingChatRoomIdIsInvalid() {
        let result = NotificationRouteParser.parseResult(
            rawPayload: ["type": "chat_message"],
            source: .remoteFCM
        )

        XCTAssertEqual(result, .invalid(reason: "missingChatRoomId", rawType: "chat_message", keys: ["type"]))
    }

    func testUnknownTypeIsInvalid() {
        let result = NotificationRouteParser.parseResult(
            rawPayload: ["type": "system"],
            source: .remoteFCM
        )

        XCTAssertEqual(result, .invalid(reason: "unknownRoute", rawType: "system", keys: ["type"]))
    }

    func testTitleBodyOnlyTestPushHasNoRoute() {
        let result = NotificationRouteParser.parseResult(
            rawPayload: [
                "title": "테스트",
                "body": "본문"
            ],
            source: .remoteFCM
        )

        XCTAssertEqual(result, .none(reason: "noCustomData", rawType: nil, keys: ["body", "title"]))
    }

    func testApsOnlyPayloadHasNoRoute() {
        let result = NotificationRouteParser.parseResult(
            userInfo: [
                "aps": [
                    "alert": [
                        "title": "테스트",
                        "body": "본문"
                    ]
                ]
            ],
            source: .remoteFCM
        )

        XCTAssertEqual(result, .none(reason: "noCustomData", rawType: nil, keys: ["body", "title"]))
    }

    func testDataKeysWinOverNotificationText() {
        let result = NotificationRouteParser.parse(
            rawPayload: [
                "title": "주문 order-should-not-be-parsed",
                "body": "post-should-not-be-parsed",
                "eventType": "post_comment",
                "postId": "post-1"
            ],
            source: .remoteFCM
        )

        XCTAssertEqual(result?.route, .communityPost(postId: "post-1", commentId: nil))
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
