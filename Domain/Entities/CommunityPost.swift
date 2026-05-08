import Foundation

struct CommunityPostSummary: Equatable, Sendable {
    let id: String
    let category: String?
    let title: String
    let content: String
    let creator: CommunityPostAuthor
    let mediaPaths: [String]
    let store: CommunityPostStoreSummary?
    let isLiked: Bool
    let likeCount: Int
    let longitude: Double?
    let latitude: Double?
    let createdAt: Date?
    let updatedAt: Date?
}

struct CommunityPostAuthor: Equatable, Sendable {
    let id: String
    let nick: String
    let profileImagePath: String?
}

struct CommunityPostStoreSummary: Equatable, Sendable {
    let id: String
    var storeId: String { id }
    let category: String?
    let name: String
    let closeTime: String?
    let imagePaths: [String]
    let isPicchelin: Bool
    let isLiked: Bool
    let likeCount: Int
    let hashTags: [String]
    let totalRating: Double?
    let totalOrderCount: Int
    let totalReviewCount: Int
    let longitude: Double?
    let latitude: Double?
}

struct CommunityPostDetail: Equatable, Sendable {
    let summary: CommunityPostSummary
    let comments: [CommunityComment]

    var totalCommentCount: Int {
        comments.reduce(0) { partialResult, comment in
            partialResult + comment.totalCountIncludingReplies
        }
    }
}

struct CommunityComment: Equatable, Sendable, Identifiable {
    let id: String
    let postID: String
    let parentCommentID: String?
    let author: CommunityPostAuthor
    let content: String
    let createdAt: Date?
    let updatedAt: Date?
    let isMine: Bool
    let isHidden: Bool
    let replies: [CommunityComment]

    var totalCountIncludingReplies: Int {
        1 + replies.reduce(0) { partialResult, reply in
            partialResult + reply.totalCountIncludingReplies
        }
    }
}

extension CommunityComment {
    init(
        id: String,
        content: String,
        createdAt: Date?,
        creator: CommunityPostAuthor,
        replies: [CommunityComment]
    ) {
        self.init(
            id: id,
            postID: "",
            parentCommentID: nil,
            author: creator,
            content: content,
            createdAt: createdAt,
            updatedAt: nil,
            isMine: false,
            isHidden: false,
            replies: replies
        )
    }

    init(
        id: String,
        content: String,
        createdAt: Date?,
        creator: CommunityPostAuthor
    ) {
        self.init(
            id: id,
            postID: "",
            parentCommentID: nil,
            author: creator,
            content: content,
            createdAt: createdAt,
            updatedAt: nil,
            isMine: false,
            isHidden: false,
            replies: []
        )
    }
}

struct CommunityPostDraftSubmission: Equatable, Sendable {
    let category: String
    let title: String
    let content: String
    let latitude: Double?
    let longitude: Double?
    let storeID: String?
    let filePaths: [String]?
}

struct CommunityPostUploadFile: Equatable, Sendable {
    let data: Data
    let fileName: String
    let mimeType: String
}

typealias CommunityPostComment = CommunityComment
typealias CommunityPostReply = CommunityComment
