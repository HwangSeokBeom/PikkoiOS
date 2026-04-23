import CoreLocation
import Foundation

enum LocationServiceError: Error, Equatable, Sendable {
    case servicesDisabled
    case authorizationNotDetermined
    case unauthorized
    case noLocationAvailable
    case underlying(String)
}

@MainActor
protocol LocationServiceProtocol: AnyObject {
    var authorizationStatus: CLAuthorizationStatus { get }
    var currentLocation: CLLocation? { get }

    func requestWhenInUseAuthorization()
    func requestCurrentLocation() async throws -> CLLocation
    func startUpdatingLocation()
    func stopUpdatingLocation()
    func locationUpdates() -> AsyncStream<CLLocation>
}
