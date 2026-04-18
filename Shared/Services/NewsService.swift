import Foundation

struct NewsHeadline: Identifiable, Hashable, Codable {
    let id: String           // url as stable id
    let title: String
    let source: String       // "NYT", "BBC", "HN"
    let url: URL
    let published: Date?
    let summary: String      // RSS description / snippet (may be html-stripped)

    init(title: String, source: String, url: URL, published: Date?, summary: String) {
        self.id = url.absoluteString
        self.title = title
        self.source = source
        self.url = url
        self.published = published
        self.summary = summary
    }
}

struct NewsFeed {
    let source: String
    let url: URL
}

@MainActor
@Observable
final class NewsService {
    static let shared = NewsService()

    /// Latest headlines per source, most recent first.
    private(set) var headlinesBySource: [String: [NewsHeadline]] = [:]
    private(set) var lastFetch: Date?
    private(set) var lastError: String?

    // Default rotation: one per source, cycled every ~20s independently.
    private(set) var activeIndex: [String: Int] = [:]

    // Three curated feeds — top-stories, no API key needed.
    let feeds: [NewsFeed] = [
        NewsFeed(source: "NYT", url: URL(string: "https://rss.nytimes.com/services/xml/rss/nyt/HomePage.xml")!),
        NewsFeed(source: "BBC", url: URL(string: "https://feeds.bbci.co.uk/news/world/rss.xml")!),
        NewsFeed(source: "HN",  url: URL(string: "https://hnrss.org/frontpage")!),
    ]

    private let cacheTTL: TimeInterval = 15 * 60
    private var rotationTimer: Timer?

    private init() {}

    func start() {
        Task { await refresh(force: false) }
        rotationTimer?.invalidate()
        rotationTimer = Timer.scheduledTimer(withTimeInterval: 22, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.rotate() }
        }
    }

    func stop() {
        rotationTimer?.invalidate()
        rotationTimer = nil
    }

    /// One headline per source, using the rotating index. Missing sources skipped.
    var currentTrio: [NewsHeadline] {
        feeds.compactMap { feed in
            guard let list = headlinesBySource[feed.source], !list.isEmpty else { return nil }
            let idx = (activeIndex[feed.source] ?? 0) % list.count
            return list[idx]
        }
    }

    func refresh(force: Bool = true) async {
        if !force, let last = lastFetch, Date().timeIntervalSince(last) < cacheTTL,
           feeds.allSatisfy({ !(headlinesBySource[$0.source]?.isEmpty ?? true) }) {
            return
        }
        await withTaskGroup(of: (String, [NewsHeadline]).self) { group in
            for feed in feeds {
                group.addTask { [feed] in
                    let items = (try? await Self.fetch(feed: feed)) ?? []
                    return (feed.source, items)
                }
            }
            for await (src, items) in group {
                if !items.isEmpty {
                    self.headlinesBySource[src] = items
                    if self.activeIndex[src] == nil { self.activeIndex[src] = 0 }
                }
            }
        }
        self.lastFetch = Date()
    }

    func rotate() {
        for feed in feeds {
            guard let list = headlinesBySource[feed.source], list.count > 1 else { continue }
            let next = ((activeIndex[feed.source] ?? 0) + 1) % list.count
            activeIndex[feed.source] = next
        }
    }

    // MARK: - RSS fetch + parse

    private static func fetch(feed: NewsFeed) async throws -> [NewsHeadline] {
        var request = URLRequest(url: feed.url)
        request.timeoutInterval = 15
        request.setValue("alfredo/1.0", forHTTPHeaderField: "User-Agent")
        let (data, _) = try await URLSession.shared.data(for: request)
        return RSSParser.parse(data: data, source: feed.source)
    }
}

// MARK: - Minimal RSS/Atom parser

private final class RSSParser: NSObject, XMLParserDelegate {
    static func parse(data: Data, source: String) -> [NewsHeadline] {
        let p = RSSParser(source: source)
        let xml = XMLParser(data: data)
        xml.delegate = p
        xml.parse()
        return p.items
    }

    private let source: String
    private(set) var items: [NewsHeadline] = []
    private var current: [String: String] = [:]
    private var inItem = false
    private var buffer = ""
    private var currentElement = ""

    init(source: String) { self.source = source }

    private static let rfc822: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
        return f
    }()
    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String : String] = [:]) {
        let name = elementName.lowercased()
        currentElement = name
        if name == "item" || name == "entry" {
            inItem = true
            current = [:]
        }
        buffer = ""
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if inItem { buffer += string }
    }

    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        if inItem, let s = String(data: CDATABlock, encoding: .utf8) { buffer += s }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        let name = elementName.lowercased()
        if inItem {
            if !buffer.isEmpty {
                current[name] = (current[name] ?? "") + buffer
            }
            if name == "item" || name == "entry" {
                if let title = current["title"]?.trimmed,
                   let linkStr = current["link"]?.trimmed,
                   let url = URL(string: linkStr) {
                    let desc = (current["description"] ?? current["summary"] ?? "").strippedHTML.trimmed
                    let dateStr = (current["pubdate"] ?? current["published"] ?? current["updated"] ?? "").trimmed
                    let published = Self.rfc822.date(from: dateStr) ?? Self.iso.date(from: dateStr)
                    items.append(NewsHeadline(
                        title: title.strippedHTML,
                        source: source,
                        url: url,
                        published: published,
                        summary: desc
                    ))
                }
                inItem = false
                current = [:]
            }
        }
        buffer = ""
    }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
    var strippedHTML: String {
        var s = self
        // strip tags
        s = s.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        // common entities
        let entities: [(String, String)] = [
            ("&nbsp;", " "), ("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"),
            ("&quot;", "\""), ("&#39;", "'"), ("&apos;", "'")
        ]
        for (k, v) in entities { s = s.replacingOccurrences(of: k, with: v) }
        return s
    }
}
