import Foundation

enum CommunityComposerMode: Equatable, Sendable {
    case create
    case edit(postID: String)
}

struct CommunityComposerRouteStoreReference: Equatable, Sendable {
    let id: String
    let name: String?
}

struct CommunityComposerRouteAttachment: Equatable, Sendable {
    let path: String
}

struct CommunityComposerInitialDraft: Equatable, Sendable {
    let title: String
    let body: String
    let categoryTitle: String?
    let store: CommunityComposerRouteStoreReference?
    let attachments: [CommunityComposerRouteAttachment]
    let latitude: Double?
    let longitude: Double?
}

enum ReviewComposerMode: Equatable, Sendable {
    case create(orderCode: String)
    case edit(reviewID: String)
}

struct ReviewComposerContext: Equatable, Sendable {
    let storeID: String
    let storeName: String?
    let mode: ReviewComposerMode
}

enum AppRoute: Equatable {
    case home
    case storeDetail(storeID: String)
    case cart(storeID: String)
    case checkout
    case orderHistory(orderID: String?)
    case orderDetail(orderID: String)
    case profile
    case community
    case communityDetail(postID: String)
    case communitySearch(query: String)
    case communityComposer(mode: CommunityComposerMode, initialDraft: CommunityComposerInitialDraft?)
    case reviewComposer(ReviewComposerContext)
    case chat(ChatTarget)
}
