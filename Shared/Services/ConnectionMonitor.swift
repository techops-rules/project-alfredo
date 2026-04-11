import Foundation
import SwiftUI
import EventKit

enum ConnectionStatus: Equatable {
    case connected
    case disconnected
    case checking
    case notConfigured
}

struct ConnectorStatus: Equatable {
    let name: String
    let icon: String // SF Symbol
    var status: ConnectionStatus
}

@MainActor
@Observable
final class ConnectionMonitor {
    static let shared = ConnectionMonitor()

    // Per-connector status
    private(set) var piStatus: ConnectionStatus = .disconnected
    private(set) var piLastSeen: Date?
    private(set) var piError: String?
    private(set) var piSuggestion: String?
    private(set) var iCloudStatus: ConnectionStatus = .disconnected
    private(set) var calendarStatus: ConnectionStatus = .disconnected

    // Convenience
    var isConnected: Bool { piStatus == .connected }

    // All connectors for UI
    var connectors: [ConnectorStatus] {
        [
            ConnectorStatus(name: "Pi", icon: "server.rack", status: piStatus),
            ConnectorStatus(name: "iCloud", icon: "icloud", status: iCloudStatus),
            ConnectorStatus(name: "Calendar", icon: "calendar", status: calendarStatus),
        ]
    }

    private var pollTimer: Timer?
    private let pollInterval: TimeInterval = 30

    private init() {
        setupNotifications()
        checkAll()
        startPolling()
    }

    private nonisolated func setupNotifications() {
        let nc = NotificationCenter.default
        #if os(iOS)
        nc.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.checkAll() }
        }
        nc.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.stopPolling() }
        }
        #elseif os(macOS)
        nc.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.checkAll() }
        }
        #endif
    }

    func checkAll() {
        checkPi()
        checkiCloud()
        checkCalendar()
    }

    // MARK: - Pi

    func checkPi() {
        let defaults = UserDefaults.standard
        guard let host = defaults.string(forKey: "terminal.piHost"), !host.isEmpty else {
            piStatus = .notConfigured
            piError = "No Pi host configured"
            piSuggestion = "Set terminal.piHost in Settings"
            return
        }
        let port = defaults.object(forKey: "terminal.piPort") as? Int ?? 8420
        guard let url = URL(string: "http://\(host):\(port)/health") else {
            piStatus = .disconnected
            piError = "Invalid host URL"
            piSuggestion = "Check terminal.piHost format"
            return
        }

        piStatus = .checking
        piError = nil
        piSuggestion = nil

        Task {
            do {
                var request = URLRequest(url: url)
                request.timeoutInterval = 5
                let (_, response) = try await URLSession.shared.data(for: request)
                if let http = response as? HTTPURLResponse {
                    if http.statusCode == 200 {
                        piStatus = .connected
                        piLastSeen = .now
                        piError = nil
                        piSuggestion = nil
                    } else if http.statusCode == 503 {
                        piStatus = .disconnected
                        piError = "Pi reachable but Claude not running (503)"
                        piSuggestion = "SSH in and run: sudo systemctl start alfredo-bridge"
                    } else {
                        piStatus = .disconnected
                        piError = "Pi returned HTTP \(http.statusCode)"
                        piSuggestion = "Check alfredo-bridge logs: journalctl -u alfredo-bridge -n 20"
                    }
                }
            } catch let error as URLError {
                piStatus = .disconnected
                switch error.code {
                case .timedOut:
                    piError = "Connection timed out"
                    piSuggestion = "Pi may be off or unreachable. Check network/Tailscale."
                case .cannotFindHost:
                    piError = "Cannot resolve \(host)"
                    piSuggestion = "Check hostname. Try IP (e.g. 100.120.26.124) or verify DNS/mDNS."
                case .cannotConnectToHost:
                    piError = "Cannot connect to \(host):\(port)"
                    piSuggestion = "Pi may be off, or bridge not running. SSH in and check."
                case .networkConnectionLost:
                    piError = "Network connection lost"
                    piSuggestion = "Check Wi-Fi or Tailscale connection."
                default:
                    piError = error.localizedDescription
                    piSuggestion = "Check Pi is on and alfredo-bridge is running."
                }
            } catch {
                piStatus = .disconnected
                piError = error.localizedDescription
                piSuggestion = "Check Pi is on and alfredo-bridge is running."
            }
        }
    }

    // Legacy compatibility
    var status: ConnectionStatus { piStatus }
    var lastSeen: Date? { piLastSeen }
    func check() { checkPi() }

    // MARK: - iCloud

    func checkiCloud() {
        iCloudStatus = iCloudService.shared.isUsingiCloud ? .connected : .disconnected
    }

    // MARK: - Calendar

    func checkCalendar() {
        let ekStatus = EKEventStore.authorizationStatus(for: .event)
        switch ekStatus {
        case .fullAccess, .authorized, .writeOnly:
            calendarStatus = .connected
        case .notDetermined:
            calendarStatus = .disconnected
        case .denied, .restricted:
            calendarStatus = .disconnected
        @unknown default:
            calendarStatus = .disconnected
        }
    }

    // MARK: - Polling

    func startPolling() {
        checkAll()
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.checkAll() }
        }
    }

    func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }
}
