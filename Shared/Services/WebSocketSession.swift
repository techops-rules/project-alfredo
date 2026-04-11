import Foundation

enum WSConnectionState: Equatable {
    case disconnected
    case connecting
    case connected
}

enum TerminalMessage {
    case output(String)
    case status(String)       // "started", "exited"
    case error(String)
    case connectionChanged(WSConnectionState)
}

/// Manages a WebSocket connection to the alfredo bridge for interactive Claude sessions.
/// Streams PTY output in real-time and sends user input bidirectionally.
@MainActor
final class WebSocketSession: ObservableObject {
    @Published var state: WSConnectionState = .disconnected

    private var task: URLSessionWebSocketTask?
    private var urlSession: URLSession?
    private var pingTask: Task<Void, Never>?
    private var receiveTask: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?
    private var reconnectDelay: TimeInterval = 1
    private let maxReconnectDelay: TimeInterval = 30
    private var intentionalDisconnect = false

    var onMessage: ((TerminalMessage) -> Void)?

    /// When true, the bridge spawns claude with the Codex agent system prompt
    var agentMode: Bool = true

    private var host: String? {
        UserDefaults.standard.string(forKey: "terminal.piHost")
    }
    private var wsPort: Int {
        // WebSocket runs on HTTP port + 1
        (UserDefaults.standard.object(forKey: "terminal.piPort") as? Int ?? 8420) + 1
    }

    var model: String {
        UserDefaults.standard.string(forKey: "terminal.model") ?? "haiku"
    }

    func connect() {
        guard let host = host, !host.isEmpty else {
            onMessage?(.error("No Pi host configured"))
            return
        }

        intentionalDisconnect = false
        state = .connecting
        onMessage?(.connectionChanged(.connecting))

        let urlString = "ws://\(host):\(wsPort)/ws"
        guard let url = URL(string: urlString) else {
            state = .disconnected
            onMessage?(.error("Invalid WebSocket URL"))
            return
        }

        let session = URLSession(configuration: .default)
        urlSession = session
        let wsTask = session.webSocketTask(with: url)
        task = wsTask

        wsTask.resume()

        // Send init message with model preference and mode
        let initMsg = try? JSONSerialization.data(withJSONObject: [
            "type": "init",
            "model": model,
            "mode": agentMode ? "agent" : "raw",
        ])
        if let data = initMsg, let str = String(data: data, encoding: .utf8) {
            wsTask.send(.string(str)) { _ in }
        }

        // Start receiving messages
        receiveTask = Task { [weak self] in
            await self?.receiveLoop()
        }

        // Start ping keepalive
        pingTask = Task { [weak self] in
            await self?.pingLoop()
        }

        // The first successful receive will confirm connection
        state = .connecting
    }

    func disconnect() {
        intentionalDisconnect = true
        cleanup()
        state = .disconnected
        onMessage?(.connectionChanged(.disconnected))
    }

    func send(_ text: String) {
        guard let task = task else { return }
        let message = try? JSONSerialization.data(withJSONObject: [
            "type": "input",
            "data": text,
        ])
        guard let data = message else { return }
        let string = String(data: data, encoding: .utf8) ?? ""
        task.send(.string(string)) { [weak self] error in
            if let error = error {
                Task { @MainActor in
                    self?.onMessage?(.error("Send failed: \(error.localizedDescription)"))
                }
            }
        }
    }

    func sendResize(cols: Int, rows: Int) {
        guard let task = task else { return }
        let message = try? JSONSerialization.data(withJSONObject: [
            "type": "resize",
            "cols": cols,
            "rows": rows,
        ] as [String: Any])
        guard let data = message, let string = String(data: data, encoding: .utf8) else { return }
        task.send(.string(string)) { _ in }
    }

    // MARK: - Receive Loop

    private func receiveLoop() async {
        guard let task = task else { return }

        // Mark as connected on first successful frame
        var didConnect = false

        while !Task.isCancelled {
            do {
                let message = try await task.receive()

                if !didConnect {
                    didConnect = true
                    state = .connected
                    reconnectDelay = 1 // reset backoff
                    onMessage?(.connectionChanged(.connected))
                }

                switch message {
                case .string(let text):
                    handleMessage(text)
                case .data(let data):
                    if let text = String(data: data, encoding: .utf8) {
                        handleMessage(text)
                    }
                @unknown default:
                    break
                }
            } catch {
                // Connection dropped
                if !intentionalDisconnect {
                    state = .disconnected
                    onMessage?(.connectionChanged(.disconnected))
                    onMessage?(.error("Connection lost: \(error.localizedDescription)"))
                    scheduleReconnect()
                }
                return
            }
        }
    }

    private func handleMessage(_ text: String) {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String else {
            // Raw text fallback
            onMessage?(.output(text))
            return
        }

        let payload = json["data"] as? String ?? ""

        switch type {
        case "output":
            onMessage?(.output(payload))
        case "status":
            onMessage?(.status(payload))
        case "error":
            onMessage?(.error(payload))
        default:
            onMessage?(.output(text))
        }
    }

    // MARK: - Ping Keepalive

    private func pingLoop() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(15))
            task?.sendPing { [weak self] error in
                if let error = error {
                    Task { @MainActor in
                        self?.onMessage?(.error("Ping failed: \(error.localizedDescription)"))
                    }
                }
            }
        }
    }

    // MARK: - Reconnect

    private func scheduleReconnect() {
        guard !intentionalDisconnect else { return }

        reconnectTask = Task { [weak self] in
            guard let self = self else { return }
            let delay = self.reconnectDelay
            self.onMessage?(.status("reconnecting in \(Int(delay))s..."))
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }

            // Exponential backoff
            self.reconnectDelay = min(self.reconnectDelay * 2, self.maxReconnectDelay)
            self.cleanup()
            self.connect()
        }
    }

    // MARK: - Cleanup

    private func cleanup() {
        pingTask?.cancel()
        pingTask = nil
        receiveTask?.cancel()
        receiveTask = nil
        reconnectTask?.cancel()
        reconnectTask = nil
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        urlSession?.invalidateAndCancel()
        urlSession = nil
    }
}
