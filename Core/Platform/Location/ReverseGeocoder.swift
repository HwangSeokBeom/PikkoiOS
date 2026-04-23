import CoreLocation
import Foundation

struct PlacemarkSummary: Equatable, Sendable {
    let name: String?
    let locality: String?
    let subLocality: String?
    let administrativeArea: String?

    var displayName: String {
        if let subLocality, let locality {
            return "\(locality) \(subLocality)"
        }

        if let locality {
            return locality
        }

        if let administrativeArea {
            return administrativeArea
        }

        return name ?? ""
    }
}

@MainActor
final class ReverseGeocoder {
    private let geocoder: CLGeocoder

    init(geocoder: CLGeocoder = CLGeocoder()) {
        self.geocoder = geocoder
    }

    func resolvePlacemarkSummary(for location: CLLocation) async throws -> PlacemarkSummary {
        let placemarks = try await geocoder.reverseGeocodeLocation(location)

        guard let placemark = placemarks.first else {
            throw CLError(.geocodeFoundNoResult)
        }

        return PlacemarkSummary(
            name: placemark.name,
            locality: placemark.locality,
            subLocality: placemark.subLocality,
            administrativeArea: placemark.administrativeArea
        )
    }

    func resolveDisplayName(for location: CLLocation) async throws -> String {
        try await resolvePlacemarkSummary(for: location).displayName
    }
}
