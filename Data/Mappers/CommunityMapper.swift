import Foundation

struct CommunityMapper: Sendable {
    private let fileURLResolver: any AuthorizedFileURLResolving
    private let dateParser: DateParser

    init(
        fileURLResolver: any AuthorizedFileURLResolving,
        dateParser: DateParser = DateParser()
    ) {
        self.fileURLResolver = fileURLResolver
        self.dateParser = dateParser
    }

    func mapPage(_ dto: CommunityPostSummaryPaginationResponseDTO) -> CursorPage<CommunityPostSummary> {
        CursorPage(
            items: dto.data.map(map),
            nextCursor: CursorPagination.normalizedCursor(dto.nextCursor)
        )
    }

    func mapList(_ dto: CommunityPostSummaryListResponseDTO) -> [CommunityPostSummary] {
        dto.data.map(map)
    }

    func mapDetail(_ dto: CommunityPostDetailResponseDTO) -> CommunityPostDetail {
        CommunityPostDetail(
            summary: mapSummary(
                postID: dto.postID,
                category: dto.category,
                title: dto.title,
                content: dto.content,
                creator: dto.creator,
                files: dto.files,
                store: dto.store,
                isLike: dto.isLike,
                likeCount: dto.likeCount,
                geolocation: dto.geolocation,
                createdAt: dto.createdAt,
                updatedAt: dto.updatedAt
            ),
            comments: dto.comments.map { mapComment($0, postID: dto.postID, parentCommentID: nil) }
        )
    }

    func mapCommentPage(
        postID: String,
        _ dto: CommunityCommentPageResponseDTO
    ) -> CursorPage<CommunityComment> {
        CursorPage(
            items: dto.data.map { mapComment($0, postID: postID, parentCommentID: nil) },
            nextCursor: CursorPagination.normalizedCursor(dto.nextCursor)
        )
    }

    func mapComment(
        postID: String,
        _ dto: CommunityCommentMutationResponseDTO,
        parentCommentID: String? = nil
    ) -> CommunityComment {
        CommunityComment(
            id: dto.commentID,
            postID: postID,
            parentCommentID: parentCommentID,
            author: map(dto.creator),
            content: dto.content,
            createdAt: dto.createdAt.flatMap(dateParser.parseISO8601),
            updatedAt: nil,
            isMine: false,
            isHidden: false,
            replies: []
        )
    }

    func map(_ dto: CommunityPostSummaryResponseDTO) -> CommunityPostSummary {
        mapSummary(
            postID: dto.postID,
            category: dto.category,
            title: dto.title,
            content: dto.content,
            creator: dto.creator,
            files: dto.files,
            store: dto.store,
            isLike: dto.isLike,
            likeCount: dto.likeCount,
            geolocation: dto.geolocation,
            createdAt: dto.createdAt,
            updatedAt: dto.updatedAt
        )
    }

    private func map(_ dto: CommunityUserInfoResponseDTO) -> CommunityPostAuthor {
        CommunityPostAuthor(
            id: dto.userID,
            nick: dto.nick,
            profileImagePath: resolvePath(dto.profileImage)
        )
    }

    private func map(_ dto: CommunityStoreSummaryDTO) -> CommunityPostStoreSummary {
        CommunityPostStoreSummary(
            id: dto.id,
            category: dto.category,
            name: dto.name,
            closeTime: dto.close,
            imagePaths: dto.storeImageURLs.compactMap(resolvePath),
            isPicchelin: dto.isPicchelin,
            isLiked: dto.isPick,
            likeCount: dto.pickCount,
            hashTags: dto.hashTags,
            totalRating: dto.totalRating,
            totalOrderCount: dto.totalOrderCount,
            totalReviewCount: dto.totalReviewCount,
            longitude: dto.geolocation?.longitude,
            latitude: dto.geolocation?.latitude
        )
    }

    private func mapComment(
        _ dto: CommunityPostCommentResponseDTO,
        postID: String,
        parentCommentID: String?
    ) -> CommunityComment {
        CommunityComment(
            id: dto.commentID,
            postID: postID,
            parentCommentID: parentCommentID,
            author: map(dto.creator),
            content: dto.content,
            createdAt: dto.createdAt.flatMap(dateParser.parseISO8601),
            updatedAt: nil,
            isMine: false,
            isHidden: false,
            replies: dto.replies.map {
                CommunityComment(
                    id: $0.commentID,
                    postID: postID,
                    parentCommentID: dto.commentID,
                    author: map($0.creator),
                    content: $0.content,
                    createdAt: $0.createdAt.flatMap(dateParser.parseISO8601),
                    updatedAt: nil,
                    isMine: false,
                    isHidden: false,
                    replies: []
                )
            }
        )
    }

    private func mapSummary(
        postID: String,
        category: String?,
        title: String,
        content: String,
        creator: CommunityUserInfoResponseDTO,
        files: [String],
        store: CommunityStoreSummaryDTO?,
        isLike: Bool,
        likeCount: Double,
        geolocation: GeolocationDTO?,
        createdAt: String?,
        updatedAt: String?
    ) -> CommunityPostSummary {
        CommunityPostSummary(
            id: postID,
            category: category,
            title: title,
            content: content,
            creator: map(creator),
            mediaPaths: files.compactMap(resolvePath),
            store: store.map(map),
            isLiked: isLike,
            likeCount: Int(likeCount.rounded()),
            longitude: geolocation?.longitude,
            latitude: geolocation?.latitude,
            createdAt: createdAt.flatMap(dateParser.parseISO8601),
            updatedAt: updatedAt.flatMap(dateParser.parseISO8601)
        )
    }

    private func resolvePath(_ path: String?) -> String? {
        guard let path, !path.isEmpty else {
            return nil
        }

        guard let resolved = try? fileURLResolver.resolveURL(from: path) else {
            return nil
        }

        return resolved.absoluteString
    }
}
