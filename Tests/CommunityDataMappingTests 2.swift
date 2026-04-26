import XCTest

@testable import Pikko

final class CommunityDataMappingTests: XCTestCase {
    func testCommunityMapperNormalizesZeroCursorToNil() {
        let mapper = CommunityMapper(
            fileURLResolver: AuthorizedFileURLResolver(
                configuration: AppConfiguration(
                    environment: .development,
                    baseURL: URL(string: "http://pickup.sesac.kr:42678")!,
                    seSACKey: "test-key"
                )
            )
        )

        let dto = CommunityPostSummaryPaginationResponseDTO(
            data: [],
            nextCursor: "0"
        )

        let page = mapper.mapPage(dto)

        XCTAssertNil(page.nextCursor)
    }

    func testCommunityMapperResolvesRelativeCommunityFilePaths() {
        let mapper = CommunityMapper(
            fileURLResolver: AuthorizedFileURLResolver(
                configuration: AppConfiguration(
                    environment: .development,
                    baseURL: URL(string: "http://pickup.sesac.kr:42678")!,
                    seSACKey: "test-key"
                )
            )
        )

        let dto = CommunityPostSummaryResponseDTO(
            postID: "post-1",
            category: "디저트",
            title: "테스트 제목",
            content: "테스트 내용",
            store: .init(
                id: "store-1",
                category: "카페",
                name: "새싹 카페",
                close: "18:00",
                storeImageURLs: ["/data/stores/cafe.jpg"],
                isPicchelin: true,
                isPick: false,
                pickCount: 1,
                hashTags: [],
                totalRating: 4.7,
                totalOrderCount: 10,
                totalReviewCount: 2,
                geolocation: .init(longitude: 127.0, latitude: 37.0)
            ),
            geolocation: .init(longitude: 127.0, latitude: 37.0),
            creator: .init(
                userID: "user-1",
                nick: "새싹",
                profileImage: "/data/profiles/avatar.jpg"
            ),
            files: ["/data/posts/post.jpg"],
            isLike: true,
            likeCount: 12,
            createdAt: "2025-07-21T14:00:00.000Z",
            updatedAt: "2025-07-21T15:30:00.000Z"
        )

        let entity = mapper.map(dto)

        XCTAssertEqual(entity.creator.profileImagePath, "http://pickup.sesac.kr:42678/v1/data/profiles/avatar.jpg")
        XCTAssertEqual(entity.mediaPaths.first, "http://pickup.sesac.kr:42678/v1/data/posts/post.jpg")
        XCTAssertEqual(entity.store?.imagePaths.first, "http://pickup.sesac.kr:42678/v1/data/stores/cafe.jpg")
    }

    func testCommunityMapperMapsDetailCommentsAndResolvesNestedPaths() {
        let mapper = CommunityMapper(
            fileURLResolver: AuthorizedFileURLResolver(
                configuration: AppConfiguration(
                    environment: .development,
                    baseURL: URL(string: "http://pickup.sesac.kr:42678")!,
                    seSACKey: "test-key"
                )
            )
        )

        let dto = CommunityPostDetailResponseDTO(
            postID: "post-42",
            category: "카페",
            title: "상세 제목",
            content: "상세 내용",
            store: nil,
            geolocation: .init(longitude: 127.1, latitude: 37.5),
            creator: .init(
                userID: "user-42",
                nick: "상세 작성자",
                profileImage: "/data/profiles/detail-author.jpg"
            ),
            files: ["/data/posts/detail.jpg"],
            isLike: false,
            likeCount: 3,
            comments: [
                .init(
                    commentID: "comment-1",
                    content: "첫 댓글",
                    createdAt: "2025-07-21T14:00:00.000Z",
                    creator: .init(
                        userID: "comment-user",
                        nick: "댓글러",
                        profileImage: "/data/profiles/comment-user.jpg"
                    ),
                    replies: [
                        .init(
                            commentID: "reply-1",
                            content: "첫 답글",
                            createdAt: "2025-07-21T15:30:00.000Z",
                            creator: .init(
                                userID: "reply-user",
                                nick: "답글러",
                                profileImage: nil
                            )
                        )
                    ]
                )
            ],
            createdAt: "2025-07-21T13:00:00.000Z",
            updatedAt: "2025-07-21T16:00:00.000Z"
        )

        let entity = mapper.mapDetail(dto)

        XCTAssertEqual(entity.summary.creator.profileImagePath, "http://pickup.sesac.kr:42678/v1/data/profiles/detail-author.jpg")
        XCTAssertEqual(entity.summary.mediaPaths.first, "http://pickup.sesac.kr:42678/v1/data/posts/detail.jpg")
        XCTAssertEqual(entity.comments.count, 1)
        XCTAssertEqual(entity.comments.first?.author.profileImagePath, "http://pickup.sesac.kr:42678/v1/data/profiles/comment-user.jpg")
        XCTAssertEqual(entity.comments.first?.replies.count, 1)
        XCTAssertEqual(entity.totalCommentCount, 2)
    }
}
