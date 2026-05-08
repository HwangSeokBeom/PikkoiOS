import Foundation

#if canImport(ActivityKit)
import ActivityKit

struct OrderLiveActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        let status: String
        let statusText: String
        let statusTitle: String
        let progressStep: Int
        let totalSteps: Int
        let displayMessage: String
        let pickupMessage: String
        let updatedAt: Date
        let canCancel: Bool
        let deepLinkURL: URL?
    }

    let orderId: String
    let orderCode: String
    let storeName: String
    let createdAt: Date
    let estimatedReadyAt: Date?
}
#endif
