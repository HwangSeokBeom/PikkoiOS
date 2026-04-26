import Foundation

@MainActor
protocol OrderDetailRouting: AnyObject {
    func routeToStoreDetail(storeID: String)
    func routeToReviewComposer(context: ReviewComposerContext)
    func routeToAuth()
    func dismissAuth()
    func clearPendingRoute()
}

@MainActor
final class OrderDetailRouter: ObservableObject, OrderDetailRouting {
    @Published private(set) var pendingRoute: AppRoute?
    @Published private(set) var isAuthPresented = false

    func routeToStoreDetail(storeID: String) {
        pendingRoute = .storeDetail(storeID: storeID)
    }

    func routeToReviewComposer(context: ReviewComposerContext) {
        pendingRoute = .reviewComposer(context)
    }

    func routeToAuth() {
        isAuthPresented = true
    }

    func dismissAuth() {
        isAuthPresented = false
    }

    func clearPendingRoute() {
        pendingRoute = nil
    }
}
