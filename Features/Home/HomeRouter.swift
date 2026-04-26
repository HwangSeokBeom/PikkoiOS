import Foundation

@MainActor
protocol HomeRouting: AnyObject {
    func routeToAuth()
    func routeToLocationPicker()
    func routeToSearch(query: String)
    func routeToBanner(_ banner: HomeBannerItem)
    func routeToStoreDetail(storeID: String)
    func clearPendingRoute()
}

enum HomeRouteDestination: Equatable {
    case storeDetail(String)
    case search(String)
    case bannerWeb(HomeBannerItem)
}

@MainActor
final class HomeRouter: ObservableObject, HomeRouting {
    @Published private(set) var pendingDestination: HomeRouteDestination?
    @Published private(set) var isAuthPresented = false

    func routeToAuth() {
        isAuthPresented = true
    }

    func routeToLocationPicker() {
        Logger.shared.debug("TODO: Connect Home location picker route.")
    }

    func routeToSearch(query: String) {
        pendingDestination = .search(query)
    }

    func routeToBanner(_ banner: HomeBannerItem) {
        guard banner.payloadType.caseInsensitiveCompare("WEBVIEW") == .orderedSame else {
            Logger.shared.debug(
                "Ignoring unsupported banner payload type. type=\(banner.payloadType) value=\(banner.payloadValue)"
            )
            return
        }

        pendingDestination = .bannerWeb(banner)
    }

    func routeToStoreDetail(storeID: String) {
        pendingDestination = .storeDetail(storeID)
    }

    func clearPendingRoute() {
        pendingDestination = nil
    }

    func dismissAuth() {
        isAuthPresented = false
    }
}
