import Foundation

struct BannerMapper: Sendable {
    private let fileURLResolver: any AuthorizedFileURLResolving

    init(fileURLResolver: any AuthorizedFileURLResolving) {
        self.fileURLResolver = fileURLResolver
    }

    func map(_ dto: BannerResponseDTO) -> Banner {
        let resolvedImagePath: String
        if let url = try? fileURLResolver.resolveURL(from: dto.imageURL) {
            resolvedImagePath = url.absoluteString
        } else {
            resolvedImagePath = dto.imageURL
        }

        return Banner(
            id: "\(dto.payload.type):\(dto.payload.value)",
            name: dto.name,
            imagePath: resolvedImagePath,
            payloadType: dto.payload.type,
            payloadValue: dto.payload.value
        )
    }
}
