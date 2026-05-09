import Foundation

struct ReviewMapper: Sendable {
    private let fileURLResolver: any AuthorizedFileURLResolving
    private let dateParser: DateParser

    init(
        fileURLResolver: any AuthorizedFileURLResolving,
        dateParser: DateParser = DateParser()
    ) {
        self.fileURLResolver = fileURLResolver
        self.dateParser = dateParser
    }

    func mapPage(_ dto: ReviewListResponseDTO) -> CursorPage<StoreReview> {
        CursorPage(
            items: dto.data.map(map),
            nextCursor: CursorPagination.normalizedCursor(dto.nextCursor)
        )
    }

    func mapRatings(_ dto: ReviewRatingListResponseDTO) -> [StoreReviewRatingBreakdown] {
        dto.data.map {
            StoreReviewRatingBreakdown(rating: $0.rating, count: $0.count)
        }
    }

    func mapUserReview(_ dto: UserReviewResponseDTO) -> UserStoreReview {
        UserStoreReview(
            id: dto.reviewID,
            store: mapStore(dto.store),
            content: dto.content,
            rating: dto.rating,
            imagePaths: dto.reviewImageURLs.compactMap(resolvePath),
            orderedMenuNames: dto.orderMenuList,
            author: .init(
                id: dto.creator.userID,
                nick: dto.creator.nick,
                profileImagePath: resolvePath(dto.creator.profileImage)
            ),
            createdAt: dto.createdAt.flatMap(dateParser.parseISO8601),
            updatedAt: dto.updatedAt.flatMap(dateParser.parseISO8601)
        )
    }

    func mapUserReviewPage(_ dto: UserReviewListResponseDTO) -> CursorPage<UserStoreReview> {
        CursorPage(
            items: dto.data.map(mapUserReview),
            nextCursor: CursorPagination.normalizedCursor(dto.nextCursor)
        )
    }

    func normalizedServerPath(from path: String) -> String {
        let trimmedPath = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPath.isEmpty else { return trimmedPath }
        guard let resolvedURL = try? fileURLResolver.resolveURL(from: trimmedPath) else {
            return trimmedPath
        }

        let pathWithQuery = resolvedURL.query.map { "\(resolvedURL.path)?\($0)" } ?? resolvedURL.path
        let apiPrefix = "/v1"
        if pathWithQuery.hasPrefix(apiPrefix + "/data/") {
            return String(pathWithQuery.dropFirst(apiPrefix.count))
        }
        return pathWithQuery.isEmpty ? trimmedPath : pathWithQuery
    }

    private func map(_ dto: ReviewResponseDTO) -> StoreReview {
        StoreReview(
            id: dto.reviewID,
            content: dto.content,
            rating: dto.rating,
            imagePaths: dto.reviewImageURLs.compactMap(resolvePath),
            orderedMenuNames: dto.orderMenuList,
            author: .init(
                id: dto.creator.userID,
                nick: dto.creator.nick,
                profileImagePath: resolvePath(dto.creator.profileImage)
            ),
            userTotalReviewCount: dto.userTotalReviewCount,
            userAverageRating: dto.userTotalRating,
            createdAt: dto.createdAt.flatMap(dateParser.parseISO8601),
            updatedAt: dto.updatedAt.flatMap(dateParser.parseISO8601)
        )
    }

    private func mapStore(_ dto: CommunityStoreSummaryDTO) -> CommunityPostStoreSummary {
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
