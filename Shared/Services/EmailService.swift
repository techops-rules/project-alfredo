import Foundation

/// Thin wrapper around the Gmail bridge on the Pi.
/// Real implementation will call the Pi bridge which has Gmail MCP access.
/// For now provides the protocol + stub so UI compiles and wires correctly.
@Observable
final class EmailService {
    static let shared = EmailService()
    private init() {}

    private var piHost: String {
        UserDefaults.standard.string(forKey: "terminal.piHost") ?? "pihub.local"
    }
    private var piPort: Int {
        UserDefaults.standard.integer(forKey: "terminal.piPort") == 0
            ? 8420
            : UserDefaults.standard.integer(forKey: "terminal.piPort")
    }
    private var baseURL: URL {
        URL(string: "http://\(piHost):\(piPort)")!
    }

    // MARK: - Fetch thread

    func fetchThread(messageId: String) async -> EmailThread? {
        guard let url = URL(string: "\(baseURL)/email/thread/\(messageId)") else { return nil }
        guard let (data, _) = try? await URLSession.shared.data(from: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }

        return parseThread(json)
    }

    // MARK: - Send reply

    func sendReply(messageId: String, threadId: String?, body: String) async -> Bool {
        guard let url = URL(string: "\(baseURL)/email/reply") else { return false }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload: [String: Any] = [
            "messageId": messageId,
            "threadId": threadId as Any,
            "body": body
        ]
        guard let httpBody = try? JSONSerialization.data(withJSONObject: payload) else { return false }
        request.httpBody = httpBody

        guard let (_, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse
        else { return false }

        return http.statusCode == 200
    }

    // MARK: - Search for email matching task text (used by enrichment)

    func searchForTask(_ taskText: String) async -> (messageId: String, subject: String, threadId: String)? {
        let query = taskText
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { $0.count > 3 }
            .prefix(4)
            .joined(separator: " ")

        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "\(baseURL)/email/search?q=\(encoded)&max=1")
        else { return nil }

        guard let (data, _) = try? await URLSession.shared.data(from: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = json["results"] as? [[String: Any]],
              let first = results.first,
              let messageId = first["id"] as? String,
              let subject = first["subject"] as? String,
              let threadId = first["threadId"] as? String
        else { return nil }

        return (messageId, subject, threadId)
    }

    // MARK: - Parse helpers

    private func parseThread(_ json: [String: Any]) -> EmailThread? {
        guard let threadId = json["threadId"] as? String,
              let msgArray = json["messages"] as? [[String: Any]]
        else { return nil }

        let messages: [EmailMessage] = msgArray.compactMap { m in
            guard let id = m["id"] as? String,
                  let from = m["from"] as? String,
                  let snippet = m["snippet"] as? String,
                  let dateString = m["date"] as? String
            else { return nil }
            return EmailMessage(
                id: id,
                from: from,
                snippet: snippet,
                dateString: dateString,
                fullBody: m["body"] as? String
            )
        }

        return EmailThread(threadId: threadId, messages: messages)
    }
}
