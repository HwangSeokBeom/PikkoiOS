import Foundation

struct StoreMapper: Sendable {
    private let fileURLResolver: any AuthorizedFileURLResolving
    private let dateParser: DateParser

    init(
        fileURLResolver: any AuthorizedFileURLResolving,
        dateParser: DateParser = DateParser()
    ) {
        self.fileURLResolver = fileURLResolver
        self.dateParser = dateParser
    }

    func map(_ dto: StoreSummaryDTO) -> StoreSummary {
        StoreSummary(
            id: dto.storeID,
            category: dto.category,
            name: dto.name,
            closeTime: dto.close,
            imagePaths: normalizedImagePaths(from: dto.storeImageURLs),
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

    func mapDetail(_ dto: StoreDetailResponseDTO) -> StoreDetail {
        StoreDetail(
            id: dto.storeID,
            category: dto.category,
            name: dto.name,
            description: dto.description,
            hashTags: dto.hashTags,
            openTime: dto.open,
            closeTime: dto.close,
            address: dto.address,
            estimatedPickupMinutes: dto.estimatedPickupTime,
            parkingGuide: dto.parkingGuide,
            imagePaths: normalizedImagePaths(from: dto.storeImageURLs),
            isPicchelin: dto.isPicchelin,
            isLiked: dto.isPick,
            likeCount: dto.pickCount,
            totalReviewCount: dto.totalReviewCount,
            totalOrderCount: dto.totalOrderCount,
            totalRating: dto.totalRating,
            owner: dto.creator.map {
                StoreOwner(
                    id: $0.userID,
                    nick: $0.nick,
                    profileImagePath: $0.profileImage.flatMap(resolveImagePath)
                )
            },
            longitude: dto.geolocation?.longitude,
            latitude: dto.geolocation?.latitude,
            menus: dto.menuList.map(map),
            createdAt: dto.createdAt.flatMap(dateParser.parseISO8601),
            updatedAt: dto.updatedAt.flatMap(dateParser.parseISO8601)
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

    private func normalizedImagePaths(from rawPaths: [String]) -> [String] {
        var seen = Set<String>()

        return rawPaths
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .compactMap(resolveImagePath)
            .filter { seen.insert($0).inserted }
    }

    private func map(_ dto: MenuResponseDTO) -> StoreMenu {
        StoreMenu(
            id: dto.menuID,
            storeID: dto.storeID,
            category: dto.category,
            name: dto.name,
            description: dto.description,
            originInformation: dto.originInformation,
            price: dto.price,
            isSoldOut: dto.isSoldOut,
            tags: dto.tags,
            imagePath: dto.menuImageURL.flatMap(resolveImagePath),
            createdAt: dto.createdAt.flatMap(dateParser.parseISO8601),
            updatedAt: dto.updatedAt.flatMap(dateParser.parseISO8601)
        )
    }
}
