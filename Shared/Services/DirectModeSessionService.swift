import Foundation

enum DirectModeState: String {
    case idle
    case listening
    case thinking
    case speaking
    case closing
}

enum DirectModeSurface: String {
    case kiosk
    case macOS
    case iOS
}

struct DirectModeEntry: Identifiable {
    enum Role {
        case system
        case user
        case assistant
    }

    let id = UUID()
    let role: Role
    let text: String
    let timestamp: Date

    static func system(_ text: String) -> DirectModeEntry {
        DirectModeEntry(role: .system, text: text, timestamp: .now)
    }

    static func user(_ text: String) -> DirectModeEntry {
        DirectModeEntry(role: .user, text: text, timestamp: .now)
    }

    static func assistant(_ text: String) -> DirectModeEntry {
        DirectModeEntry(role: .assistant, text: text, timestamp: .now)
    }
}

@MainActor
final class DirectModeSessionService: ObservableObject {
    static let shared = DirectModeSessionService()

    @Published private(set) var state: DirectModeState = .idle
    @Published private(set) var entries: [DirectModeEntry] = []
    @Published private(set) var lastTranscript = ""
    @Published private(set) var lastReply = ""
    @Published private(set) var sessionID: String?
    @Published private(set) var currentSurface: DirectModeSurface?
    @Published private(set) var expiresAt: Date?

    private let contextService = DirectModeContextService.shared
    private let idleTimeout: TimeInterval = 5 * 60
    private var expiryTimer: Timer?
    private var voiceObserver: Any?

    private init() {
        voiceObserver = NotificationCenter.default.addObserver(
            forName: .voiceEvent,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let event = notification.userInfo?["event"] as? VoiceEventService.VoiceEvent else { return }
            Task { @MainActor in
                self?.ingestRemoteVoiceEvent(event)
            }
        }
    }

    deinit {
        if let voiceObserver {
            NotificationCenter.default.removeObserver(voiceObserver)
        }
        expiryTimer?.invalidate()
    }

    var isActive: Bool {
        state != .idle && sessionID != nil
    }

    func start(surface: DirectModeSurface, trigger: String) {
        if sessionID == nil {
            sessionID = UUID().uuidString
            entries.append(.system("direct mode active // \(surface.rawValue) // \(trigger)"))
        } else {
            entries.append(.system("direct mode extended // \(trigger)"))
        }
        currentSurface = surface
        state = .listening
        extendSession()
    }

    func handleTranscript(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if !isActive {
            start(surface: currentSurface ?? .iOS, trigger: "manual")
        }

        if isStopPhrase(trimmed) {
            end(reason: "stopped by user")
            return
        }

        lastTranscript = trimmed
        entries.append(.user(trimmed))
        state = .thinking
        extendSession()

        Task {
            await sendPrompt(for: trimmed)
        }
    }

    func handleReply(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        lastReply = trimmed
        entries.append(.assistant(trimmed))
        state = .speaking
        extendSession()

        Task { @MainActor in
            try? await Task.sleep(for: .seconds(0.4))
            if self.isActive {
                self.state = .listening
            }
        }
    }

    func end(reason: String) {
        guard isActive else { return }
        state = .closing
        entries.append(.system("direct mode closed // \(reason)"))
        expiryTimer?.invalidate()
        expiryTimer = nil
        expiresAt = nil

        Task { @MainActor in
            try? await Task.sleep(for: .seconds(0.4))
            self.state = .idle
            self.sessionID = nil
            self.currentSurface = nil
        }
    }

    private func extendSession() {
        let expiry = Date().addingTimeInterval(idleTimeout)
        expiresAt = expiry
        expiryTimer?.invalidate()
        expiryTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
            Task { @MainActor in
                guard let self else {
                    timer.invalidate()
                    return
                }
                guard let expiresAt = self.expiresAt else {
                    timer.invalidate()
                    return
                }
                if Date() >= expiresAt {
                    timer.invalidate()
                    self.end(reason: "idle timeout")
                }
            }
        }
    }

    private func sendPrompt(for transcript: String) async {
        let defaults = UserDefaults.standard
        guard let host = defaults.string(forKey: "terminal.piHost"), !host.isEmpty else {
            entries.append(.system("direct mode unavailable // pi host not configured"))
            state = .listening
            return
        }

        let port = defaults.object(forKey: "terminal.piPort") as? Int ?? 8420
        guard let url = URL(string: "http://\(host):\(port)/chat") else {
            entries.append(.system("direct mode unavailable // invalid bridge url"))
            state = .listening
            return
        }

        let prompt = buildPrompt(for: transcript)

        do {
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.timeoutInterval = 120
            request.httpBody = try JSONSerialization.data(withJSONObject: [
                "prompt": prompt,
                "mode": "agent",
                "conversation_mode": "direct",
                "session_id": sessionID ?? UUID().uuidString,
            ])

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                entries.append(.system("direct mode unavailable // bridge returned an error"))
                state = .listening
                return
            }

            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            let reply = (json?["response"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            handleReply(reply?.isEmpty == false ? reply! : "I didn't get anything back from the bridge.")
        } catch {
            entries.append(.system("direct mode send failed // \(error.localizedDescription)"))
            state = .listening
        }
    }

    private func buildPrompt(for transcript: String) -> String {
        let context = contextService.snapshot().promptBlock
        let history = entries
            .suffix(8)
            .filter { $0.role != .system }
            .map { entry in
                let role: String
                switch entry.role {
                case .system: role = "system"
                case .user: role = "user"
                case .assistant: role = "assistant"
                }
                return "- \(role): \(entry.text)"
            }
            .joined(separator: "\n")

        return """
        [Alfredo Direct Mode]
        You are in an explicit multi-turn direct conversation with Todd.
        Stay concise, useful, and conversational. This is Slice 1: read-only answers only. Do not claim to create reminders, tasks, travel routes, or calendar changes.
        If asked for action-taking beyond read-only advice, explain that Direct Mode capture lands in the next slice.

        Surface: \(currentSurface?.rawValue ?? "unknown")
        Session ID: \(sessionID ?? "none")

        \(context)

        [RECENT CONVERSATION]
        \(history.isEmpty ? "- user: (new direct mode session)" : history)
        [/RECENT CONVERSATION]

        [LATEST USER TURN]
        \(transcript)
        [/LATEST USER TURN]
        """
    }

    private func ingestRemoteVoiceEvent(_ event: VoiceEventService.VoiceEvent) {
        guard event.mode == "direct" else { return }

        if sessionID == nil, let remoteSessionID = event.sessionID {
            sessionID = remoteSessionID
            currentSurface = .kiosk
        }

        if let remoteSessionID = event.sessionID {
            sessionID = remoteSessionID
        }

        switch event.type {
        case "session":
            state = .listening
            entries.append(.system(event.text.isEmpty ? "direct mode active // kiosk" : event.text))
            extendSession()
        case "listening", "wake":
            state = .listening
            extendSession()
        case "command":
            if !event.text.isEmpty {
                lastTranscript = event.text
                entries.append(.user(event.text))
                state = .thinking
                extendSession()
            }
        case "reply":
            let replyText = event.reply.isEmpty ? event.text : event.reply
            if !replyText.isEmpty {
                handleReply(replyText)
            }
        case "dismissed", "idle":
            if event.sessionState == "closing" || event.text.lowercased().contains("direct mode closed") {
                end(reason: "kiosk session ended")
            }
        default:
            break
        }
    }

    private func isStopPhrase(_ text: String) -> Bool {
        let normalized = text.lowercased()
        let phrases = [
            "stop",
            "that's enough",
            "thats enough",
            "got it",
            "thank you",
            "thanks",
            "okay that's enough",
            "ok that's enough"
        ]
        return phrases.contains(where: normalized.contains)
    }
}
