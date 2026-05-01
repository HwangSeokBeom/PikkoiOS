import Foundation

@MainActor
protocol HomeRouting: AnyObject {
    func routeToAuth()
    func routeToLocationPicker()
    func routeToLocationPermissionSettings()
    func routeToLocationSearch()
    func routeToNotificationList()
    func routeToSearch(query: String)
    func routeToBanner(_ banner: HomeBannerItem)
    func routeToStoreDetail(storeID: String)
    func clearPendingRoute()
}

enum HomeRouteDestination: Equatable {
    case storeDetail(String)
    case search(String)
    case bannerWeb(HomeBannerItem)
    case locationSearch
    case notificationList
}

@MainActor
final class HomeRouter: ObservableObject, HomeRouting {
    @Published private(set) var pendingDestination: HomeRouteDestination?
    @Published private(set) var isAuthPresented = false
    @Published private(set) var isLocationPickerPresented = false
    @Published private(set) var isLocationPermissionSettingsPresented = false

    func routeToAuth() {
        isAuthPresented = true
    }

    func routeToLocationPicker() {
        isLocationPickerPresented = true
    }

    func routeToLocationPermissionSettings() {
        isLocationPermissionSettingsPresented = true
    }

    func routeToLocationSearch() {
        pendingDestination = .locationSearch
    }

    func routeToNotificationList() {
        Logger(category: "NotificationBell").debugVerbose("[NotificationBell] tapped")
        pendingDestination = .notificationList
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

    func dismissLocationPicker() {
        isLocationPickerPresented = false
    }

    func dismissLocationPermissionSettings() {
        isLocationPermissionSettingsPresented = false
    }
}
