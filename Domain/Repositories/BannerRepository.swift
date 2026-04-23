import Foundation

protocol BannerRepository: Sendable {
    func fetchMainBanners() async throws -> [Banner]
}
