import MapKit
import Foundation

@MainActor
final class MapLauncher: MapLauncherProtocol {
    func openMap(at destination: MapDestination) {
        let item = mapItem(for: destination)
        item.openInMaps()
    }

    func openDirections(to destination: MapDestination, transportType: MapTransportType = .automobile) {
        let item = mapItem(for: destination)
        item.openInMaps(launchOptions: [
            MKLaunchOptionsDirectionsModeKey: transportType.directionsMode
        ])
    }

    private func mapItem(for destination: MapDestination) -> MKMapItem {
        let placemark = MKPlacemark(coordinate: destination.coordinate)
        let item = MKMapItem(placemark: placemark)
        item.name = destination.name
        return item
    }
}

private extension MapTransportType {
    var directionsMode: String {
        switch self {
        case .automobile:
            return MKLaunchOptionsDirectionsModeDriving
        case .walking:
            return MKLaunchOptionsDirectionsModeWalking
        case .transit:
            return MKLaunchOptionsDirectionsModeTransit
        }
    }
}
