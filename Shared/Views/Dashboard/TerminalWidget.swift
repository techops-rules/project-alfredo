import SwiftUI

/// Terminal widget that connects to Claude Code running on a remote host (e.g. Raspberry Pi)
/// via HTTP. Presents a monospaced terminal-style interface within the canvas.
///
/// Offline-first: caches conversation history locally, queues messages when
/// disconnected, and auto-sends when the Pi becomes reachable.
struct TerminalWidget: View {
    @Environment(\.theme) private var theme
    @StateObject private var session = TerminalSession()

    var body: some View {
        WidgetShell(title: session.widgetTitle, badge: session.statusBadge, zone: "system") {
            VStack(spacing: 0) {
                // Connection status bar
                HStack(spacing: 6) {
                    Circle()
                        .fill(session.statusColor)
                        .frame(width: 5, height: 5)
                    Text(session.connectionLabel)
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundColor(ThemeManager.textSecondary)
                    Spacer()
                    if !session.pendingCount.isEmpty {
                        Text(session.pendingCount)
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(ThemeManager.warning)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(ThemeManager.surface.opacity(0.4))

                // Output area
                ScrollViewReader { proxy in
                    ScrollView(.vertical, showsIndicators: false) {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(session.lines) { line in
                                terminalLine(line)
                                    .id(line.id)
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                    }
                    .onChange(of: session.lines.count) { _, _ in
                        if let last = session.lines.last {
                            withAnimation(.easeOut(duration: 0.15)) {
                                proxy.scrollTo(last.id, anchor: .bottom)
                            }
                        }
                    }
                }

                // Input area
                Divider()
                    .background(theme.accentBorder)

                HStack(spacing: 6) {
                    Text(">")
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundColor(theme.accentFull)

                    TerminalTextField(
                        text: $session.inputText,
                        placeholder: "ask claude...",
                        onSubmit: { session.send() }
                    )
                    .frame(maxWidth: .infinity)

                    // Status indicator
                    Circle()
                        .fill(session.statusColor)
                        .frame(width: 6, height: 6)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(ThemeManager.background.opacity(0.5))
            }
        }
    }

    @ViewBuilder
    private func terminalLine(_ line: TerminalLine) -> some View {
        HStack(alignment: .top, spacing: 6) {
            if line.isUser {
                Text(">")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(theme.accentFull)
            } else if line.isSystem {
                Text("#")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(ThemeManager.textSecondary)
            } else {
                Text(" ")
                    .font(.system(size: 11, design: .monospaced))
            }

            Text(line.text)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(line.color)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 1)
    }
}

// MARK: - Terminal Data

struct TerminalLine: Identifiable {
    let id = UUID()
    let text: String
    let isUser: Bool
    let isSystem: Bool
    let isError: Bool
    let timestamp: Date

    var color: Color {
        if isError { return ThemeManager.danger }
        if isSystem { return ThemeManager.textSecondary }
        if isUser { return ThemeManager.textEmphasis }
        return ThemeManager.textPrimary
    }

    static func user(_ text: String) -> TerminalLine {
        TerminalLine(text: text, isUser: true, isSystem: false, isError: false, timestamp: .now)
    }
    static func response(_ text: String) -> TerminalLine {
        TerminalLine(text: text, isUser: false, isSystem: false, isError: false, timestamp: .now)
    }
    static func system(_ text: String) -> TerminalLine {
        TerminalLine(text: text, isUser: false, isSystem: true, isError: false, timestamp: .now)
    }
    static func error(_ text: String) -> TerminalLine {
        TerminalLine(text: text, isUser: false, isSystem: false, isError: true, timestamp: .now)
    }
}

// MARK: - Terminal Session

@MainActor
final class TerminalSession: ObservableObject {
    @Published var lines: [TerminalLine] = []
    @Published var inputText = ""
    @Published var isLoading = false

    private let monitor = ConnectionMonitor.shared
    private let cache = TerminalCache.shared
    private var pendingMessages: [String] = []
    private var isFlushing = false

    // WebSocket session for interactive mode
    private let wsSession = WebSocketSession()
    private var useWebSocket = false
    private var useAgentMode = true
    private var voiceObserver: Any?

    var statusBadge: String? {
        if isLoading { return "..." }
        if !pendingMessages.isEmpty { return "\(pendingMessages.count)Q" }
        if useWebSocket {
            switch wsSession.state {
            case .connected: return "LIVE"
            case .connecting: return "..."
            case .disconnected: return "OFF"
            }
        }
        switch monitor.status {
        case .connected: return "ON"
        case .checking: return "..."
        case .disconnected, .notConfigured: return "OFF"
        }
    }

    var statusColor: Color {
        if useWebSocket {
            switch wsSession.state {
            case .connected: return ThemeManager.success
            case .connecting: return ThemeManager.warning
            case .disconnected: return ThemeManager.textSecondary.opacity(0.3)
            }
        }
        switch monitor.status {
        case .connected: return ThemeManager.success
        case .checking: return ThemeManager.warning
        case .disconnected, .notConfigured: return ThemeManager.textSecondary.opacity(0.3)
        }
    }

    var connectionLabel: String {
        let host = UserDefaults.standard.string(forKey: "terminal.piHost") ?? ""
        if useWebSocket {
            switch wsSession.state {
            case .connected: return "pi:\(host) \u{2714} interactive"
            case .connecting: return "connecting to \(host)..."
            case .disconnected:
                if host.isEmpty { return "pi: not configured" }
                return "pi:\(host) \u{2716} offline"
            }
        }
        switch monitor.status {
        case .connected: return "pi:\(host) \u{2714}"
        case .checking: return "connecting to \(host)..."
        case .notConfigured: return "pi: not configured"
        case .disconnected: return "pi:\(host) \u{2716} offline"
        }
    }

    var widgetTitle: String {
        useAgentMode ? "ALFREDO.TTY" : "CLAUDE.TTY"
    }

    var pendingCount: String {
        pendingMessages.isEmpty ? "" : "\(pendingMessages.count) queued"
    }

    init() {
        // Restore cached conversation
        let cached = cache.load()
        for line in cached.lines {
            lines.append(TerminalLine(
                text: line.text, isUser: line.isUser, isSystem: line.isSystem,
                isError: line.isError, timestamp: line.timestamp
            ))
        }
        pendingMessages = cached.pendingMessages

        // Sync agent mode to WebSocket session
        wsSession.agentMode = useAgentMode

        if lines.isEmpty {
            if useAgentMode {
                lines.append(.system("ALFREDO.TTY v0.4"))
                lines.append(.system("agent mode // codex system prompt active"))
            } else {
                lines.append(.system("CLAUDE.TTY v0.4"))
                lines.append(.system("interactive terminal for claude code"))
            }
        }

        if !pendingMessages.isEmpty {
            lines.append(.system("\(pendingMessages.count) queued message(s) waiting to send"))
        }

        // Set up WebSocket message handler
        wsSession.onMessage = { [weak self] message in
            Task { @MainActor in
                self?.handleWSMessage(message)
            }
        }

        // Listen for voice events from VoiceEventService
        voiceObserver = NotificationCenter.default.addObserver(
            forName: .voiceEvent, object: nil, queue: .main
        ) { [weak self] notif in
            guard let event = notif.userInfo?["event"] as? VoiceEventService.VoiceEvent else { return }
            Task { @MainActor in
                self?.handleVoiceEvent(event)
            }
        }

        // Try WebSocket connection after a brief delay
        Task {
            try? await Task.sleep(for: .seconds(1))
            attemptWebSocket()
        }
    }

    nonisolated func cleanup() {
        // Called externally if needed; observers are cleaned up automatically
    }

    // MARK: - Voice Events

    private func handleVoiceEvent(_ event: VoiceEventService.VoiceEvent) {
        let prefix = event.mode == "direct" ? "DIRECT" : "🎙"
        switch event.type {
        case "wake":
            lines.append(.system("\(prefix) \(event.text)"))
        case "listening":
            lines.append(.system("\(prefix) listening..."))
        case "command":
            lines.append(.user(event.text))
        case "reply":
            let replyText = event.reply.isEmpty ? event.text : event.reply
            lines.append(.response(replyText))
        case "session":
            lines.append(.system(event.text.isEmpty ? "DIRECT mode active" : event.text))
        case "idle":
            lines.append(.system("\(prefix) \(event.text)"))
        default:
            break
        }
        saveCache()
    }

    // MARK: - WebSocket

    private func attemptWebSocket() {
        let host = UserDefaults.standard.string(forKey: "terminal.piHost") ?? ""
        guard !host.isEmpty else { return }

        useWebSocket = true
        lines.append(.system("connecting to pi via websocket..."))
        wsSession.connect()
    }

    private func handleWSMessage(_ message: TerminalMessage) {
        switch message {
        case .output(let text):
            // Stream output line by line
            let cleaned = ANSIParser.strip(text)
            let outputLines = cleaned.components(separatedBy: "\n")
            for line in outputLines {
                if !line.isEmpty {
                    lines.append(.response(line))
                }
            }
            isLoading = false
            saveCache()

        case .status(let status):
            switch status {
            case "started":
                lines.append(.system("claude session started"))
                isLoading = false
                // Flush any queued messages
                if !pendingMessages.isEmpty {
                    flushQueue()
                }
            case "exited":
                lines.append(.system("claude session ended"))
                isLoading = false
            default:
                lines.append(.system(status))
            }
            saveCache()

        case .error(let error):
            lines.append(.error(error))
            isLoading = false
            saveCache()

        case .connectionChanged(let state):
            switch state {
            case .connected:
                lines.append(.system("websocket connected"))
            case .connecting:
                break // don't spam
            case .disconnected:
                lines.append(.system("websocket disconnected"))
                isLoading = false
            }
            saveCache()
        }
    }

    // MARK: - Send

    func send() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        lines.append(.user(text))
        inputText = ""

        if text.starts(with: "/") {
            handleCommand(text)
            saveCache()
            return
        }

        if useWebSocket && wsSession.state == .connected {
            isLoading = true
            wsSession.send(text + "\n")
        } else if monitor.isConnected {
            sendToRemoteHTTP(text)
        } else {
            pendingMessages.append(text)
            lines.append(.system("(queued \u{2014} will send when connected)"))
            saveCache()
        }
    }

    private func flushQueue() {
        guard !pendingMessages.isEmpty else { return }
        isFlushing = true
        lines.append(.system("sending \(pendingMessages.count) queued message(s)"))

        let toSend = pendingMessages
        pendingMessages.removeAll()
        saveCache()

        for message in toSend {
            lines.append(.user(message))
            if useWebSocket && wsSession.state == .connected {
                wsSession.send(message + "\n")
            }
        }
        isFlushing = false
    }

    // MARK: - Commands

    private func handleCommand(_ command: String) {
        switch command.lowercased() {
        case "/clear":
            lines.removeAll()
            lines.append(.system("cleared"))
        case "/status":
            let host = UserDefaults.standard.string(forKey: "terminal.piHost") ?? "(not set)"
            let port = UserDefaults.standard.object(forKey: "terminal.piPort") as? Int ?? 8420
            lines.append(.system("host: \(host):\(port)"))
            lines.append(.system("mode: \(useWebSocket ? "websocket (interactive)" : "http (one-shot)")"))
            lines.append(.system("agent: \(useAgentMode ? "on (codex prompt)" : "off (raw)")"))
            lines.append(.system("model: \(wsSession.model)"))
            lines.append(.system("ws state: \(wsSession.state)"))
            lines.append(.system("pi status: \(monitor.status == .connected ? "reachable" : "unreachable")"))
            if let lastSeen = monitor.lastSeen {
                let formatter = RelativeDateTimeFormatter()
                formatter.unitsStyle = .short
                lines.append(.system("last seen: \(formatter.localizedString(for: lastSeen, relativeTo: .now))"))
            }
            lines.append(.system("cached lines: \(lines.count)"))
            lines.append(.system("queued: \(pendingMessages.count)"))
        case "/connect":
            if useWebSocket {
                wsSession.disconnect()
                wsSession.connect()
                lines.append(.system("reconnecting websocket..."))
            } else {
                monitor.check()
                lines.append(.system("checking connection..."))
            }
        case "/ws":
            if !useWebSocket {
                attemptWebSocket()
            } else {
                lines.append(.system("already in websocket mode"))
            }
        case "/http":
            if useWebSocket {
                wsSession.disconnect()
                useWebSocket = false
                lines.append(.system("switched to http mode"))
            } else {
                lines.append(.system("already in http mode"))
            }
        case "/agent":
            if !useAgentMode {
                useAgentMode = true
                wsSession.agentMode = true
                lines.append(.system("switched to agent mode (codex system prompt)"))
                lines.append(.system("reconnect (/connect) to apply"))
            } else {
                lines.append(.system("already in agent mode"))
            }
        case "/raw":
            if useAgentMode {
                useAgentMode = false
                wsSession.agentMode = false
                lines.append(.system("switched to raw mode (no system prompt)"))
                lines.append(.system("reconnect (/connect) to apply"))
            } else {
                lines.append(.system("already in raw mode"))
            }
        case _ where command.lowercased().hasPrefix("/model"):
            let parts = command.split(separator: " ", maxSplits: 1)
            if parts.count < 2 {
                let current = UserDefaults.standard.string(forKey: "terminal.model") ?? "haiku"
                lines.append(.system("current model: \(current)"))
                lines.append(.system("usage: /model haiku|sonnet|opus"))
            } else {
                let model = String(parts[1]).lowercased().trimmingCharacters(in: .whitespaces)
                let valid = ["haiku", "sonnet", "opus"]
                if valid.contains(model) {
                    UserDefaults.standard.set(model, forKey: "terminal.model")
                    lines.append(.system("model set to \(model)"))
                    lines.append(.system("reconnect (/connect) to use new model"))
                } else {
                    lines.append(.error("unknown model: \(model)"))
                    lines.append(.system("valid models: haiku, sonnet, opus"))
                }
            }
        case "/help":
            lines.append(.system("/clear    - clear terminal"))
            lines.append(.system("/status   - connection info"))
            lines.append(.system("/connect  - reconnect"))
            lines.append(.system("/model    - change model (haiku/sonnet/opus)"))
            lines.append(.system("/ws       - switch to websocket (interactive)"))
            lines.append(.system("/http     - switch to http (one-shot)"))
            lines.append(.system("/agent    - agent mode (codex system prompt)"))
            lines.append(.system("/raw      - raw mode (no system prompt)"))
            lines.append(.system("/help     - show commands"))
            lines.append(.system(""))
            lines.append(.system("anything else goes to alfredo"))
        default:
            lines.append(.error("unknown command: \(command)"))
            lines.append(.system("type /help for available commands"))
        }
    }

    // MARK: - HTTP Fallback

    private func sendToRemoteHTTP(_ text: String) {
        isLoading = true
        Task {
            let defaults = UserDefaults.standard
            guard let host = defaults.string(forKey: "terminal.piHost") else {
                lines.append(.error("no host configured"))
                isLoading = false
                return
            }
            let port = defaults.object(forKey: "terminal.piPort") as? Int ?? 8420
            guard let url = URL(string: "http://\(host):\(port)/chat") else {
                lines.append(.error("invalid host url"))
                isLoading = false
                return
            }

            do {
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.timeoutInterval = 120
                request.httpBody = try JSONSerialization.data(withJSONObject: ["prompt": text])

                let (data, response) = try await URLSession.shared.data(for: request)

                if let http = response as? HTTPURLResponse, http.statusCode == 200 {
                    if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let reply = json["response"] as? String {
                        let cleaned = ANSIParser.strip(reply)
                        for line in cleaned.components(separatedBy: "\n") {
                            lines.append(.response(line))
                        }
                    } else if let raw = String(data: data, encoding: .utf8) {
                        lines.append(.response(raw))
                    }
                } else {
                    let code = (response as? HTTPURLResponse)?.statusCode ?? 0
                    lines.append(.error("pi returned status \(code)"))
                }
            } catch {
                lines.append(.error("send failed: \(error.localizedDescription)"))
                pendingMessages.append(text)
                lines.append(.system("(re-queued for retry)"))
            }
            isLoading = false
            saveCache()
        }
    }

    private func saveCache() {
        cache.save(lines: lines, pending: pendingMessages)
    }
}
