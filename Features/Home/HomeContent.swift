import Foundation

struct HomeContent: Sendable {
    let locationLabel: String
    let popularKeywords: [String]
    let banners: [Banner]
    let popularStores: [StoreSummary]
    let nearbyStoresPage: CursorPage<StoreSummary>
}
