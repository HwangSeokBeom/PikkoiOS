import CoreLocation
import Foundation
import MapKit

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

struct PikkoSelectedLocation: Equatable, Sendable, Identifiable {
    let id: String
    let title: String
    let subtitle: String?
    let latitude: Double
    let longitude: Double
    let regionID: String?
    let source: String

    init(
        id: String = UUID().uuidString,
        title: String,
        subtitle: String?,
        latitude: Double,
        longitude: Double,
        regionID: String? = nil,
        source: String = "manual"
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.latitude = latitude
        self.longitude = longitude
        self.regionID = regionID
        self.source = source
    }

    var displayName: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "선택한 위치" : title
    }
}

@MainActor
final class SelectedLocationStore {
    static let shared = SelectedLocationStore()

    private let storageKey = "home.selectedLocation"
    private let defaults: UserDefaults

    private init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var selectedLocation: PikkoSelectedLocation? {
        guard let data = defaults.data(forKey: storageKey),
              let stored = try? JSONDecoder().decode(StoredSelectedLocation.self, from: data) else {
            return nil
        }

        return PikkoSelectedLocation(
            id: stored.id,
            title: stored.title,
            subtitle: stored.subtitle,
            latitude: stored.latitude,
            longitude: stored.longitude,
            regionID: stored.regionID,
            source: stored.source ?? "persisted"
        )
    }

    func save(_ location: PikkoSelectedLocation) {
        let stored = StoredSelectedLocation(location: location)
        guard let data = try? JSONEncoder().encode(stored) else { return }
        defaults.set(data, forKey: storageKey)
        NotificationCenter.default.post(name: .pikkoSelectedLocationDidChange, object: location)
    }

    func clear() {
        defaults.removeObject(forKey: storageKey)
        NotificationCenter.default.post(name: .pikkoSelectedLocationDidChange, object: nil)
    }
}

private struct StoredSelectedLocation: Codable {
    let id: String
    let title: String
    let subtitle: String?
    let latitude: Double
    let longitude: Double
    let regionID: String?
    let source: String?

    init(location: PikkoSelectedLocation) {
        id = location.id
        title = location.title
        subtitle = location.subtitle
        latitude = location.latitude
        longitude = location.longitude
        regionID = location.regionID
        source = location.source
    }
}

enum LocationDefaults {
    static let defaultSelectedLocation = PikkoSelectedLocation(
        id: "default-sesac-yeongdeungpo",
        title: "청년취업사관학교 영등포캠퍼스",
        subtitle: "서울 영등포구 선유로9길 30",
        latitude: 37.517833,
        longitude: 126.886270,
        regionID: "sesac-ydp",
        source: "default"
    )

    static var searchRegion: MKCoordinateRegion {
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(
                latitude: defaultSelectedLocation.latitude,
                longitude: defaultSelectedLocation.longitude
            ),
            span: MKCoordinateSpan(latitudeDelta: 0.8, longitudeDelta: 0.8)
        )
    }
}

extension Notification.Name {
    static let pikkoSelectedLocationDidChange = Notification.Name("pikkoSelectedLocationDidChange")
}
