import Foundation
import UserNotifications

/// Polls the Pi kiosk server for voice events (wake word detections, commands, replies)
/// and surfaces them to the app via notifications and local alerts.
@Observable
final class VoiceEventService {
    static let shared = VoiceEventService()

    struct VoiceEvent {
        let type: String    // wake, listening, command, reply, idle
        let text: String
        let reply: String
        let timestamp: TimeInterval
        let mode: String
        let sessionID: String?
        let surface: String?
        let sessionState: String?
    }

    private(set) var lastEvent: VoiceEvent?
    private(set) var isListening = false
    private var sinceTimestamp: TimeInterval = Date().timeIntervalSince1970
    private var pollTimer: Timer?

    private init() {}

    func start() {
        guard pollTimer == nil else { return }
        pollTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.poll()
        }
        poll()
    }

    func stop() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    private func poll() {
        let host = UserDefaults.standard.string(forKey: "terminal.piHost") ?? ""
        guard !host.isEmpty else { return }

        // Use the kiosk port (8430) for voice events
        let urlStr = "http://\(host):8430/proxy/voice-event?since=\(sinceTimestamp)"
        guard let url = URL(string: urlStr) else { return }

        var request = URLRequest(url: url)
        request.timeoutInterval = 5

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self, let data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let events = json["events"] as? [[String: Any]],
                  !events.isEmpty else { return }

            DispatchQueue.main.async {
                for event in events {
                    let type = event["type"] as? String ?? ""
                    let text = event["text"] as? String ?? ""
                    let reply = event["reply"] as? String ?? ""
                    let ts = event["timestamp"] as? TimeInterval ?? 0
                    let mode = event["mode"] as? String ?? "voice"
                    let sessionID = event["session_id"] as? String
                    let surface = event["surface"] as? String
                    let sessionState = event["session_state"] as? String

                    self.sinceTimestamp = max(self.sinceTimestamp, ts + 0.001)

                    let voiceEvent = VoiceEvent(
                        type: type,
                        text: text,
                        reply: reply,
                        timestamp: ts,
                        mode: mode,
                        sessionID: sessionID,
                        surface: surface,
                        sessionState: sessionState
                    )
                    self.lastEvent = voiceEvent
                    self.isListening = type == "listening"

                    // Post notification for the terminal widget to pick up
                    NotificationCenter.default.post(
                        name: .voiceEvent,
                        object: nil,
                        userInfo: ["event": voiceEvent]
                    )

                    // Show local notification for wake/reply events when app is backgrounded
                    #if os(iOS)
                    if type == "wake" || type == "reply" {
                        self.showLocalNotification(type: type, text: type == "reply" ? reply : text)
                    }
                    #endif
                }
            }
        }.resume()
    }

    #if os(iOS)
    private func showLocalNotification(type: String, text: String) {
        let content = UNMutableNotificationContent()
        content.title = type == "wake" ? "🎙 Alfredo" : "💬 Alfredo"
        content.body = text
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "voice-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }
    #endif
}

extension Notification.Name {
    static let voiceEvent = Notification.Name("alfredo.voiceEvent")
}
