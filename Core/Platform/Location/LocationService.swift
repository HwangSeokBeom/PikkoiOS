import CoreLocation
import Foundation

@MainActor
final class LocationService: NSObject, LocationServiceProtocol {
    private let locationManager: CLLocationManager
    private var locationContinuations: [UUID: AsyncStream<CLLocation>.Continuation] = [:]
    private var pendingLocationRequest: CheckedContinuation<CLLocation, Error>?

    private(set) var currentLocation: CLLocation?

    var authorizationStatus: CLAuthorizationStatus {
        locationManager.authorizationStatus
    }

    init(locationManager: CLLocationManager = CLLocationManager()) {
        self.locationManager = locationManager
        super.init()
        self.locationManager.delegate = self
        self.locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func requestWhenInUseAuthorization() {
        guard CLLocationManager.locationServicesEnabled() else { return }
        locationManager.requestWhenInUseAuthorization()
    }

    func requestCurrentLocation() async throws -> CLLocation {
        guard CLLocationManager.locationServicesEnabled() else {
            throw LocationServiceError.servicesDisabled
        }

        switch authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            if let currentLocation {
                return currentLocation
            }

            return try await withCheckedThrowingContinuation { continuation in
                pendingLocationRequest = continuation
                locationManager.requestLocation()
            }
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
            throw LocationServiceError.authorizationNotDetermined
        case .restricted, .denied:
            throw LocationServiceError.unauthorized
        @unknown default:
            throw LocationServiceError.unauthorized
        }
    }

    func startUpdatingLocation() {
        guard CLLocationManager.locationServicesEnabled() else { return }
        locationManager.startUpdatingLocation()
    }

    func stopUpdatingLocation() {
        locationManager.stopUpdatingLocation()
    }

    func locationUpdates() -> AsyncStream<CLLocation> {
        AsyncStream { continuation in
            let identifier = UUID()
            locationContinuations[identifier] = continuation
            continuation.onTermination = { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.locationContinuations.removeValue(forKey: identifier)
                }
            }
        }
    }

    private func finishPendingLocationRequest(with result: Result<CLLocation, Error>) {
        guard let pendingLocationRequest else { return }
        self.pendingLocationRequest = nil

        switch result {
        case .success(let location):
            pendingLocationRequest.resume(returning: location)
        case .failure(let error):
            pendingLocationRequest.resume(throwing: error)
        }
    }
}

extension LocationService: @preconcurrency CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let latestLocation = locations.last else {
            finishPendingLocationRequest(with: .failure(LocationServiceError.noLocationAvailable))
            return
        }

        currentLocation = latestLocation
        locationContinuations.values.forEach { $0.yield(latestLocation) }
        finishPendingLocationRequest(with: .success(latestLocation))
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: any Error) {
        Logger.shared.warning("Location update failed: \(error.localizedDescription)")
        finishPendingLocationRequest(with: .failure(LocationServiceError.underlying(error.localizedDescription)))
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard authorizationStatus == .denied || authorizationStatus == .restricted else {
            return
        }

        finishPendingLocationRequest(with: .failure(LocationServiceError.unauthorized))
    }
}
