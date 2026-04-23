import Foundation

struct StoreMapper: Sendable {
    private let fileURLResolver: any AuthorizedFileURLResolving

    init(fileURLResolver: any AuthorizedFileURLResolving) {
        self.fileURLResolver = fileURLResolver
    }

    func map(_ dto: StoreSummaryDTO) -> StoreSummary {
        StoreSummary(
            id: dto.storeID,
            category: dto.category,
            name: dto.name,
            closeTime: dto.close,
            imagePaths: dto.storeImageURLs.compactMap(resolveImagePath),
            isPicchelin: dto.isPicchelin,
            isLiked: dto.isPick,
            likeCount: dto.pickCount,
            hashTags: dto.hashTags,
            totalRating: dto.totalRating,
            totalOrderCount: dto.totalOrderCount,
            totalReviewCount: dto.totalReviewCount,
            longitude: dto.geolocation?.longitude,
            latitude: dto.geolocation?.latitude,
            distanceMeters: dto.distance
        )
    }

    func mapPage(_ dto: StoreSummaryListResponseDTO) -> CursorPage<StoreSummary> {
        CursorPage(
            items: dto.data.map { self.map($0) },
            nextCursor: normalize(cursor: dto.nextCursor)
        )
    }

    private func normalize(cursor: String?) -> String? {
        guard let cursor = cursor?.trimmingCharacters(in: .whitespacesAndNewlines),
              !cursor.isEmpty,
              cursor != "0" else {
            return nil
        }

        return cursor
    }

    private func resolveImagePath(_ path: String) -> String? {
        guard let resolved = try? fileURLResolver.resolveURL(from: path) else {
            return nil
        }
        return resolved.absoluteString
    }
}
