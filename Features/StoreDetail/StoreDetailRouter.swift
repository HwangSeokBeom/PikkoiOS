import Foundation

@MainActor
protocol StoreDetailRouting: AnyObject {
    func routeToAuth()
    func routeToDirections(
        storeName: String,
        address: String?,
        latitude: Double?,
        longitude: Double?
    )
    func routeToChat(storeID: String)
    func routeToCart(storeID: String)
    func routeToReviewComposer(context: ReviewComposerContext)
    func clearPendingRoute()
}

@MainActor
final class StoreDetailRouter: ObservableObject, StoreDetailRouting {
    @Published private(set) var pendingRoute: AppRoute?
    @Published private(set) var isAuthPresented = false
    private let mapLauncher: any MapLauncherProtocol

    init(mapLauncher: any MapLauncherProtocol) {
        self.mapLauncher = mapLauncher
    }

    func routeToAuth() {
        isAuthPresented = true
    }

    func routeToDirections(
        storeName: String,
        address: String?,
        latitude: Double?,
        longitude: Double?
    ) {
        guard let latitude, let longitude else {
            Logger.shared.warning("StoreDetail directions route skipped because coordinates are missing for store=\(storeName)")
            return
        }

        mapLauncher.openDirections(
            to: MapDestination(
                latitude: latitude,
                longitude: longitude,
                name: storeName,
                address: address
            ),
            transportType: .automobile
        )
        Logger.shared.info("Opened external directions for store=\(storeName)")
    }

    func routeToChat(storeID: String) {
        pendingRoute = .chat(storeID: storeID)
    }

    func routeToCart(storeID: String) {
        pendingRoute = .cart(storeID: storeID)
    }

    func routeToReviewComposer(context: ReviewComposerContext) {
        pendingRoute = .reviewComposer(context)
    }

    func clearPendingRoute() {
        pendingRoute = nil
    }

    func dismissAuth() {
        isAuthPresented = false
    }
}
