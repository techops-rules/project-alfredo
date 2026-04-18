import Foundation

/// Minimal helper for calling the Pi bridge `/chat` endpoint.
/// Mirrors the contract described in the project CLAUDE.md:
///   POST http://<host>:<port>/chat  {"prompt":"..."} -> {"response":"..."}
enum ClaudeBridgeClient {
    static var piHost: String {
        UserDefaults.standard.string(forKey: "terminal.piHost") ?? "pihub.local"
    }
    static var piPort: Int {
        let stored = UserDefaults.standard.integer(forKey: "terminal.piPort")
        return stored == 0 ? 8420 : stored
    }

    static func ask(prompt: String, timeout: TimeInterval = 30) async throws -> String {
        guard let url = URL(string: "http://\(piHost):\(piPort)/chat") else {
            throw BridgeError.badURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = timeout
        request.httpBody = try JSONSerialization.data(withJSONObject: ["prompt": prompt])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw BridgeError.badResponse
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let reply = json["response"] as? String else {
            throw BridgeError.parseError
        }
        return reply
    }

    enum BridgeError: Error, LocalizedError {
        case badURL, badResponse, parseError
        var errorDescription: String? {
            switch self {
            case .badURL: return "bridge url is invalid"
            case .badResponse: return "bridge returned a non-200"
            case .parseError: return "bridge response wasn't JSON with a 'response' field"
            }
        }
    }
}
