import Foundation

@MainActor
protocol ProfileRouting: AnyObject {
    func routeToLikedStores()
    func routeToMyPosts(userID: String)
    func routeToLikedPosts()
    func routeToMyReviews(userID: String)
    func clearPendingRoute()
}

@MainActor
final class ProfileRouter: ObservableObject, ProfileRouting {
    @Published private(set) var isLikedStoresPresented = false
    @Published private(set) var presentedMyPostsUserID: String?
    @Published private(set) var isLikedPostsPresented = false
    @Published private(set) var presentedMyReviewsUserID: String?

    func routeToLikedStores() {
        guard !isLikedStoresPresented else { return }
        isLikedStoresPresented = true
    }

    func routeToMyPosts(userID: String) {
        guard presentedMyPostsUserID == nil else { return }
        presentedMyPostsUserID = userID
    }

    func routeToLikedPosts() {
        guard !isLikedPostsPresented else { return }
        isLikedPostsPresented = true
    }

    func routeToMyReviews(userID: String) {
        guard presentedMyReviewsUserID == nil else { return }
        presentedMyReviewsUserID = userID
    }

    func clearPendingRoute() {
        isLikedStoresPresented = false
        presentedMyPostsUserID = nil
        isLikedPostsPresented = false
        presentedMyReviewsUserID = nil
    }
}
