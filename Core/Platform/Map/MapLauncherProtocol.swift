import CoreLocation
import Foundation

struct MapDestination: Equatable, Sendable {
    let latitude: Double
    let longitude: Double
    let name: String?
    let address: String?

    init(latitude: Double, longitude: Double, name: String? = nil, address: String? = nil) {
        self.latitude = latitude
        self.longitude = longitude
        self.name = name
        self.address = address
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

enum MapTransportType: Sendable {
    case automobile
    case walking
    case transit
}

@MainActor
protocol MapLauncherProtocol: AnyObject {
    func openMap(at destination: MapDestination)
    func openDirections(to destination: MapDestination, transportType: MapTransportType)
}
