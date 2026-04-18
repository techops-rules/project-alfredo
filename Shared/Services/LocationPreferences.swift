import Foundation
import CoreLocation

/// Geocoding + current-location helper for weather location overrides.
/// Write results through WeatherService.setLocation(lat:lon:label:).
@MainActor
final class LocationPreferences: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let shared = LocationPreferences()

    @Published var lastError: String?
    @Published var isResolving = false

    private let geocoder = CLGeocoder()
    private let manager = CLLocationManager()
    private var pendingCurrent: ((Result<CLLocation, Error>) -> Void)?

    override init() {
        super.init()
        manager.delegate = self
    }

    /// Resolve a freeform query (zip, city, "Portland, OR") to coords + label.
    func setLocation(from query: String) async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        isResolving = true
        lastError = nil
        defer { isResolving = false }

        do {
            let placemarks = try await geocoder.geocodeAddressString(trimmed)
            guard let p = placemarks.first,
                  let loc = p.location else {
                lastError = "couldn't find that location"
                return
            }
            let label = Self.label(from: p, fallback: trimmed)
            WeatherService.shared.setLocation(
                lat: loc.coordinate.latitude,
                lon: loc.coordinate.longitude,
                label: label
            )
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Request current-location authorization and resolve once.
    func useCurrentLocation() {
        isResolving = true
        lastError = nil
        pendingCurrent = { [weak self] result in
            Task { @MainActor in
                guard let self else { return }
                defer { self.isResolving = false }
                switch result {
                case .failure(let err):
                    self.lastError = err.localizedDescription
                case .success(let loc):
                    // Reverse-geocode for a friendly label
                    let label = (try? await self.reverseLabel(for: loc)) ?? "current"
                    WeatherService.shared.setLocation(
                        lat: loc.coordinate.latitude,
                        lon: loc.coordinate.longitude,
                        label: label
                    )
                }
            }
        }

        let status = manager.authorizationStatus
        switch status {
        case .notDetermined:
            #if os(iOS)
            manager.requestWhenInUseAuthorization()
            #else
            manager.requestAlwaysAuthorization()
            #endif
        case .denied, .restricted:
            pendingCurrent?(.failure(NSError(domain: "location", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "location permission denied. enable it in Settings."])))
            pendingCurrent = nil
        default:
            manager.requestLocation()
        }
    }

    private func reverseLabel(for loc: CLLocation) async throws -> String {
        let placemarks = try await geocoder.reverseGeocodeLocation(loc)
        guard let p = placemarks.first else { return "current" }
        return Self.label(from: p, fallback: "current")
    }

    private static func label(from p: CLPlacemark, fallback: String) -> String {
        if let zip = p.postalCode, !zip.isEmpty { return zip }
        if let city = p.locality, let state = p.administrativeArea { return "\(city), \(state)" }
        if let city = p.locality { return city }
        return fallback
    }

    // MARK: - CLLocationManagerDelegate

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        Task { @MainActor in
            self.pendingCurrent?(.success(loc))
            self.pendingCurrent = nil
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            self.pendingCurrent?(.failure(error))
            self.pendingCurrent = nil
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        let ok: Bool
        #if os(iOS)
        ok = (status == .authorizedWhenInUse || status == .authorizedAlways)
        #else
        ok = (status == .authorizedAlways)
        #endif
        guard ok else {
            Task { @MainActor in
                if let pending = self.pendingCurrent {
                    pending(.failure(NSError(domain: "location", code: 2,
                        userInfo: [NSLocalizedDescriptionKey: "location permission denied"])))
                    self.pendingCurrent = nil
                }
            }
            return
        }
        manager.requestLocation()
    }
}
