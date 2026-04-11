import Foundation
import EventKit

// MARK: - Models

enum ContextSourceType: String, Codable {
    case calendarNotes
    case calendarRecurrence
    case email
    case taskBoard
    case memory
    case unknown
}

struct ContextSource: Identifiable {
    let id = UUID()
    let title: String
    let snippet: String
    let sourceType: ContextSourceType
    let url: URL?
    let confidence: Double
    let timestamp: Date
}

struct MeetingBriefing {
    let event: CalendarEvent
    let summary: String
    let contextSources: [ContextSource]
    let overallConfidence: Double
    let generatedAt: Date
    let isPreloaded: Bool
}

// MARK: - Service

@Observable
final class MeetingPrepService {
    static let shared = MeetingPrepService()

    /// Cached briefings keyed by event ID
    private var cache: [String: MeetingBriefing] = [:]
    private var loadingEvents: Set<String> = []

    private let eventStore = EKEventStore()
    private let taskBoard = TaskBoardService()

    private init() {}

    var isLoading: Bool { !loadingEvents.isEmpty }

    func isLoadingEvent(_ id: String) -> Bool { loadingEvents.contains(id) }

    func cachedBriefing(for eventId: String) -> MeetingBriefing? {
        cache[eventId]
    }

    /// Pre-load briefings for all of today's events (called from morning briefing or on appear)
    func preloadTodaysBriefings(events: [CalendarEvent]) {
        for event in events where !event.isPast && event.attendance != .declined {
            if cache[event.id] == nil {
                Task { await prepareBriefing(for: event) }
            }
        }
    }

    /// Prepare a briefing for a single event
    @MainActor
    func prepareBriefing(for event: CalendarEvent) async -> MeetingBriefing {
        // Return cached if available
        if let cached = cache[event.id] { return cached }

        loadingEvents.insert(event.id)
        defer { loadingEvents.remove(event.id) }

        var sources: [ContextSource] = []

        // 1. Calendar invite notes (confidence: 0.95)
        if let notes = event.notes, !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let snippet = String(notes.prefix(200))
            sources.append(ContextSource(
                title: "Calendar invite notes",
                snippet: snippet,
                sourceType: .calendarNotes,
                url: nil,
                confidence: applyRecency(base: 0.95, date: event.startTime),
                timestamp: event.startTime
            ))
        }

        // 2. Previous recurrence notes (confidence: 0.85)
        if event.isRecurring {
            let prevNotes = await fetchPreviousRecurrenceNotes(for: event)
            for (note, date) in prevNotes {
                sources.append(ContextSource(
                    title: "Previous meeting notes",
                    snippet: String(note.prefix(200)),
                    sourceType: .calendarRecurrence,
                    url: nil,
                    confidence: applyRecency(base: 0.85, date: date),
                    timestamp: date
                ))
            }
        }

        // 3. Task board matches (confidence: 0.6)
        let taskMatches = searchTaskBoard(for: event)
        for match in taskMatches {
            sources.append(match)
        }

        // 4. Memory file matches (confidence: 0.65)
        let memoryMatches = searchMemoryFiles(for: event)
        for match in memoryMatches {
            sources.append(match)
        }

        // Sort by confidence
        sources.sort { $0.confidence > $1.confidence }

        // Calculate overall confidence
        let topSources = Array(sources.prefix(5))
        let overall = topSources.isEmpty ? 0.0 :
            topSources.reduce(0.0) { $0 + $1.confidence } / Double(topSources.count)

        // Generate summary
        let summary = generateSummary(event: event, sources: topSources)

        let briefing = MeetingBriefing(
            event: event,
            summary: summary,
            contextSources: sources,
            overallConfidence: min(1.0, max(0.0, overall)),
            generatedAt: Date(),
            isPreloaded: true
        )

        cache[event.id] = briefing
        return briefing
    }

    // MARK: - Context Gathering

    private func fetchPreviousRecurrenceNotes(for event: CalendarEvent) async -> [(String, Date)] {
        guard CalendarService.shared.isAuthorized else { return [] }

        let cal = Calendar.current
        let twoWeeksAgo = cal.date(byAdding: .day, value: -14, to: Date()) ?? Date()
        let yesterday = cal.date(byAdding: .day, value: -1, to: event.startTime) ?? Date()

        let predicate = eventStore.predicateForEvents(
            withStart: twoWeeksAgo, end: yesterday, calendars: nil
        )
        let pastEvents = eventStore.events(matching: predicate)

        // Find events with same title (recurring series)
        let matches = pastEvents
            .filter { $0.title == event.title }
            .sorted { ($0.startDate ?? Date.distantPast) > ($1.startDate ?? Date.distantPast) }
            .prefix(2)

        return matches.compactMap { ek in
            guard let notes = ek.notes, !notes.isEmpty else { return nil }
            return (notes, ek.startDate ?? Date())
        }
    }

    private func searchTaskBoard(for event: CalendarEvent) -> [ContextSource] {
        taskBoard.reload()
        let keywords = extractKeywords(from: event)
        var results: [ContextSource] = []

        for task in taskBoard.todayTasks + taskBoard.workTasks {
            let text = task.displayText.lowercased()
            for keyword in keywords where text.contains(keyword) {
                let relevance: Double = event.title.lowercased().contains(keyword) ? 0.8 : 0.5
                results.append(ContextSource(
                    title: "Task: \(task.displayText)",
                    snippet: "Task Board > \(task.isDone ? "Done" : "Today")",
                    sourceType: .taskBoard,
                    url: nil,
                    confidence: applyRecency(base: 0.6, date: Date()) * relevance,
                    timestamp: Date()
                ))
                break // one match per task
            }
        }

        return Array(results.prefix(3))
    }

    private func searchMemoryFiles(for event: CalendarEvent) -> [ContextSource] {
        let keywords = extractKeywords(from: event)
        var results: [ContextSource] = []

        // Search both memory locations
        let paths = [
            iCloudService.shared.memoryURL,
            URL(fileURLWithPath: NSHomeDirectory())
                .appendingPathComponent(".claude/projects/-Users-todd-Projects-project-alfredo/memory/MEMORY.md")
        ]

        for path in paths {
            guard let content = try? String(contentsOf: path, encoding: .utf8) else { continue }
            let lines = content.components(separatedBy: .newlines)

            for line in lines {
                let lower = line.lowercased()
                for keyword in keywords where lower.contains(keyword) && line.count > 5 {
                    results.append(ContextSource(
                        title: "Memory: \(path.lastPathComponent)",
                        snippet: String(line.prefix(150)),
                        sourceType: .memory,
                        url: path,
                        confidence: applyRecency(base: 0.65, date: Date()),
                        timestamp: Date()
                    ))
                    break
                }
            }
        }

        return Array(results.prefix(2))
    }

    // MARK: - Helpers

    private func extractKeywords(from event: CalendarEvent) -> [String] {
        var keywords: [String] = []

        // Title words (skip common ones)
        let stopWords: Set = ["the", "a", "an", "and", "or", "for", "with", "meeting", "call", "sync", "check", "in", "on", "at", "to"]
        let titleWords = event.title.lowercased()
            .components(separatedBy: .alphanumerics.inverted)
            .filter { $0.count > 2 && !stopWords.contains($0) }
        keywords.append(contentsOf: titleWords)

        // Attendee names
        if let attendees = event.attendeeNames {
            for name in attendees {
                let parts = name.lowercased().components(separatedBy: " ")
                keywords.append(contentsOf: parts.filter { $0.count > 2 })
            }
        }

        return Array(Set(keywords))
    }

    private func applyRecency(base: Double, date: Date) -> Double {
        let daysSince = abs(date.timeIntervalSinceNow) / 86400
        let recencyMultiplier = max(0.5, 1.0 - (daysSince / 14.0))
        return base * recencyMultiplier
    }

    private func generateSummary(event: CalendarEvent, sources: [ContextSource]) -> String {
        if sources.isEmpty {
            return "No additional context found for this event."
        }

        var parts: [String] = []

        if let notes = sources.first(where: { $0.sourceType == .calendarNotes }) {
            parts.append(notes.snippet)
        }

        let attendeeCount = event.attendeeNames?.count ?? 0
        if attendeeCount > 0 {
            parts.append("\(attendeeCount) attendee\(attendeeCount == 1 ? "" : "s")")
        }

        if sources.contains(where: { $0.sourceType == .taskBoard }) {
            parts.append("Related tasks found on board.")
        }

        return parts.joined(separator: " · ")
    }

    /// Clear cache (e.g. on day change)
    func clearCache() {
        cache.removeAll()
    }
}
