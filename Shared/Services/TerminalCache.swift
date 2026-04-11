import Foundation

struct CachedLine: Codable {
    let text: String
    let isUser: Bool
    let isSystem: Bool
    let isError: Bool
    let timestamp: Date
}

struct CachedConversation: Codable {
    var lines: [CachedLine]
    var pendingMessages: [String]

    static let empty = CachedConversation(lines: [], pendingMessages: [])
}

@MainActor
final class TerminalCache {
    static let shared = TerminalCache()

    private let maxLines = 200
    private var fileURL: URL {
        iCloudService.shared.baseURL.appendingPathComponent(".config/terminal-history.json")
    }

    private init() {}

    func load() -> CachedConversation {
        guard let data = iCloudService.shared.readFileData(at: fileURL),
              let cached = try? JSONDecoder().decode(CachedConversation.self, from: data) else {
            return .empty
        }
        return cached
    }

    func save(lines: [TerminalLine], pending: [String]) {
        let cached = CachedConversation(
            lines: Array(lines.suffix(maxLines)).map { line in
                CachedLine(text: line.text, isUser: line.isUser, isSystem: line.isSystem, isError: line.isError, timestamp: line.timestamp)
            },
            pendingMessages: pending
        )
        guard let data = try? JSONEncoder().encode(cached) else { return }
        iCloudService.shared.writeFileData(data, to: fileURL)
    }

    func savePending(_ pending: [String]) {
        var conversation = load()
        conversation.pendingMessages = pending
        guard let data = try? JSONEncoder().encode(conversation) else { return }
        iCloudService.shared.writeFileData(data, to: fileURL)
    }
}
