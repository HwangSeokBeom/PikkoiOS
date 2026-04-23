import Foundation

@MainActor
protocol HomeRouting: AnyObject {
    func routeToLocationPicker()
    func routeToSearch(query: String)
    func routeToBanner(id: String)
    func routeToStoreDetail(storeID: String)
}

@MainActor
final class HomeRouter: ObservableObject, HomeRouting {
    @Published private(set) var pendingRoute: AppRoute?

    func routeToLocationPicker() {
        Logger.shared.debug("TODO: Connect Home location picker route.")
    }

    func routeToSearch(query: String) {
        Logger.shared.debug("TODO: Connect Home search route. query=\(query)")
    }

    func routeToBanner(id: String) {
        Logger.shared.debug("TODO: Connect Home banner route. bannerID=\(id)")
    }

    func routeToStoreDetail(storeID: String) {
        pendingRoute = .storeDetail(storeID: storeID)
        Logger.shared.debug("TODO: Connect HomeRouter store detail destination mapping.")
    }
}
