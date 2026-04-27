import CoreLocation
import Foundation

@MainActor
final class LocationService: NSObject, LocationServiceProtocol {
    private let locationManager: CLLocationManager
    private var locationContinuations: [UUID: AsyncStream<CLLocation>.Continuation] = [:]
    private var pendingLocationRequest: CheckedContinuation<CLLocation, Error>?
    private var cachedAuthorizationStatus: CLAuthorizationStatus = .notDetermined
    private var hasRequestedAuthorization = false

    private(set) var currentLocation: CLLocation?

    var authorizationStatus: CLAuthorizationStatus {
        cachedAuthorizationStatus
    }

    init(locationManager: CLLocationManager = CLLocationManager()) {
        self.locationManager = locationManager
        super.init()
        self.locationManager.delegate = self
        self.locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        self.cachedAuthorizationStatus = locationManager.authorizationStatus
    }

    deinit {
        pendingLocationRequest?.resume(throwing: LocationServiceError.noLocationAvailable)
        pendingLocationRequest = nil
        locationContinuations.values.forEach { $0.finish() }
        locationContinuations.removeAll()
    }

    func requestWhenInUseAuthorization() {
        guard cachedAuthorizationStatus == .notDetermined,
              !hasRequestedAuthorization else {
            return
        }
        hasRequestedAuthorization = true
        Task { [weak self] in
            guard let self else { return }
            let servicesEnabled = await Self.locationServicesEnabled()
            self.requestAuthorizationIfPossible(servicesEnabled: servicesEnabled)
        }
    }

    func requestCurrentLocation() async throws -> CLLocation {
        guard await Self.locationServicesEnabled() else {
            throw LocationServiceError.servicesDisabled
        }

        switch authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            if let currentLocation {
                return currentLocation
            }

            return try await withCheckedThrowingContinuation { continuation in
                finishPendingLocationRequest(with: .failure(LocationServiceError.noLocationAvailable))
                pendingLocationRequest = continuation
                locationManager.requestLocation()
            }
        case .notDetermined:
            throw LocationServiceError.authorizationNotDetermined
        case .restricted, .denied:
            throw LocationServiceError.unauthorized
        @unknown default:
            throw LocationServiceError.unauthorized
        }
    }

    func startUpdatingLocation() {
        switch cachedAuthorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            Task { [weak self] in
                guard let self else { return }
                let servicesEnabled = await Self.locationServicesEnabled()
                self.startUpdatingLocationIfPossible(servicesEnabled: servicesEnabled)
            }
        case .notDetermined:
            requestWhenInUseAuthorization()
        case .restricted, .denied:
            return
        @unknown default:
            return
        }
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

    private func requestAuthorizationIfPossible(servicesEnabled: Bool) {
        guard hasRequestedAuthorization else { return }
        guard servicesEnabled else {
            hasRequestedAuthorization = false
            return
        }
        guard cachedAuthorizationStatus == .notDetermined else {
            hasRequestedAuthorization = false
            return
        }
        locationManager.requestWhenInUseAuthorization()
    }

    private func startUpdatingLocationIfPossible(servicesEnabled: Bool) {
        guard servicesEnabled else { return }
        switch cachedAuthorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            locationManager.startUpdatingLocation()
        case .notDetermined:
            requestWhenInUseAuthorization()
        case .restricted, .denied:
            return
        @unknown default:
            return
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

    nonisolated private static func locationServicesEnabled() async -> Bool {
        await Task.detached(priority: .utility) {
            CLLocationManager.locationServicesEnabled()
        }.value
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
        cachedAuthorizationStatus = manager.authorizationStatus
        hasRequestedAuthorization = false

        switch cachedAuthorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            if pendingLocationRequest != nil {
                manager.requestLocation()
            }
        case .denied, .restricted:
            finishPendingLocationRequest(with: .failure(LocationServiceError.unauthorized))
        case .notDetermined:
            break
        @unknown default:
            finishPendingLocationRequest(with: .failure(LocationServiceError.unauthorized))
        }
    }
}
