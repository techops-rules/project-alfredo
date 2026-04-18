import Foundation

/// Simple JSON-backed reading list — saved headlines for later.
@MainActor
@Observable
final class ReadingListService {
    static let shared = ReadingListService()

    private(set) var items: [NewsHeadline] = []

    private let fileURL: URL = {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return dir.appendingPathComponent("reading-list.json")
    }()

    private init() { load() }

    var count: Int { items.count }

    func contains(_ headline: NewsHeadline) -> Bool {
        items.contains { $0.id == headline.id }
    }

    @discardableResult
    func toggle(_ headline: NewsHeadline) -> Bool {
        if let idx = items.firstIndex(where: { $0.id == headline.id }) {
            items.remove(at: idx)
            save()
            return false
        } else {
            items.insert(headline, at: 0)
            save()
            return true
        }
    }

    func remove(_ headline: NewsHeadline) {
        items.removeAll { $0.id == headline.id }
        save()
    }

    // MARK: - Persistence

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        items = (try? JSONDecoder().decode([NewsHeadline].self, from: data)) ?? []
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(items) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
