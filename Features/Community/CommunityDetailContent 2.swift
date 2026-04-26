import Foundation

struct CommunityDetailContent: Equatable {
    let detail: CommunityPostDetail
    let distanceMeters: Double?

    static func fallback(postID: String) -> CommunityDetailContent {
        CommunityDetailContent(
            detail: CommunityPostDetail(
                summary: CommunityPostSummary(
                    id: postID,
                    category: "디저트",
                    title: "상세 API 연결 전 fallback 게시글",
                    content: "postID를 기준으로 실제 feature root는 열렸고, 이 fallback은 preview와 안전한 개발 검증용으로만 남겨둡니다.",
                    creator: CommunityPostAuthor(
                        id: "preview-user",
                        nick: "픽코 커뮤니티",
                        profileImagePath: "community-detail-author-\(postID)"
                    ),
                    mediaPaths: [
                        "community-detail-media-\(postID)-1",
                        "community-detail-media-\(postID)-2",
                        "community-detail-media-\(postID)-3"
                    ],
                    store: CommunityPostStoreSummary(
                        id: "preview-store",
                        category: "카페",
                        name: "다음 단계",
                        closeTime: "18:00",
                        imagePaths: ["community-detail-store-\(postID)"],
                        isPicchelin: false,
                        isLiked: false,
                        likeCount: 0,
                        hashTags: ["#preview"],
                        totalRating: 4.5,
                        totalOrderCount: 10,
                        totalReviewCount: 3,
                        longitude: nil,
                        latitude: nil
                    ),
                    isLiked: false,
                    likeCount: 0,
                    longitude: nil,
                    latitude: nil,
                    createdAt: nil,
                    updatedAt: nil
                ),
                comments: [
                    CommunityPostComment(
                        id: "preview-comment",
                        postID: postID,
                        parentCommentID: nil,
                        author: CommunityPostAuthor(
                            id: "preview-comment-user",
                            nick: "새싹 댓글러",
                            profileImagePath: nil
                        ),
                        content: "댓글 API와 상세 본문 API는 이 root 위에 바로 확장할 수 있습니다.",
                        createdAt: nil,
                        updatedAt: nil,
                        isMine: false,
                        isHidden: false,
                        replies: []
                    )
                ]
            ),
            distanceMeters: nil
        )
    }
}

enum CommunityDetailCommentFeatureError: Error, Equatable {
    case authenticationRequired
    case validation(message: String)
    case forbidden(message: String)
    case notFound(message: String)
    case unavailable(message: String)
}

extension CommunityDetailCommentFeatureError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .authenticationRequired:
            return "로그인 후 댓글을 이용할 수 있어요."
        case .validation(let message),
             .forbidden(let message),
             .notFound(let message),
             .unavailable(let message):
            return message
        }
    }
}

enum CommunityDetailFeatureError: Error, Equatable {
    case authenticationRequired
    case notFound(message: String)
    case unavailable(message: String)
}

extension CommunityDetailFeatureError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .authenticationRequired:
            return "로그인 후 게시글 상세를 확인할 수 있어요."
        case .notFound(let message), .unavailable(let message):
            return message
        }
    }
}
