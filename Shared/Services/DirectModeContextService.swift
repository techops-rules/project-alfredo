import Foundation

struct DirectModeContextSnapshot {
    let generatedAt: Date
    let todaySummary: String
    let tomorrowSummary: String
    let activeProjectsSummary: String
    let openTasksSummary: String
    let recentMemorySummary: String

    @MainActor var promptBlock: String {
        """
        [DIRECT MODE CONTEXT]
        Generated: \(DirectModeContextService.timestampFormatter.string(from: generatedAt))

        TODAY
        \(todaySummary)

        TOMORROW
        \(tomorrowSummary)

        OPEN TASKS
        \(openTasksSummary)

        ACTIVE PROJECTS
        \(activeProjectsSummary)

        RECENT MEMORY
        \(recentMemorySummary)
        [/DIRECT MODE CONTEXT]
        """
    }
}

@MainActor
final class DirectModeContextService {
    static let shared = DirectModeContextService()

    private let icloud = iCloudService.shared
    private let calendarService = CalendarService.shared
    private let projectService = ProjectService.shared

    static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    private init() {}

    func snapshot(now: Date = .now) -> DirectModeContextSnapshot {
        DirectModeContextSnapshot(
            generatedAt: now,
            todaySummary: todaySummary(now: now),
            tomorrowSummary: tomorrowSummary(now: now),
            activeProjectsSummary: activeProjectsSummary(),
            openTasksSummary: openTasksSummary(),
            recentMemorySummary: recentMemorySummary()
        )
    }

    func todaySummary(now: Date = .now) -> String {
        summarizeEvents(on: now)
    }

    func tomorrowSummary(now: Date = .now) -> String {
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: now) ?? now
        return summarizeEvents(on: tomorrow)
    }

    func activeProjectsSummary() -> String {
        let projects = projectService.activeProjects
        guard !projects.isEmpty else { return "No active projects tracked right now." }

        return projects.prefix(6).map { project in
            let target = project.target.isEmpty ? "no target" : project.target
            return "- \(project.name) // \(project.status.rawValue) // \(project.percent)% // target \(target)"
        }
        .joined(separator: "\n")
    }

    func openTasksSummary() -> String {
        let taskBoard = TaskBoardService()
        let groups: [(String, [AppTask])] = [
            ("Today", Array(taskBoard.todayTasks.prefix(5))),
            ("Soon", Array(taskBoard.soonTasks.prefix(3))),
            ("Waiting", Array(taskBoard.waitingTasks.prefix(3)))
        ]

        let lines = groups.compactMap { label, tasks -> String? in
            guard !tasks.isEmpty else { return nil }
            let joined = tasks.map(\.displayText).joined(separator: " | ")
            return "- \(label): \(joined)"
        }

        return lines.isEmpty ? "No open tasks on the board." : lines.joined(separator: "\n")
    }

    func recentMemorySummary() -> String {
        let repoMemoryURL = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent(".claude/projects/-Users-todd-Projects-project-alfredo/memory/MEMORY.md")
        let sources = [icloud.memoryURL, repoMemoryURL]

        for url in sources {
            guard let content = try? String(contentsOf: url, encoding: .utf8) else { continue }
            let bullets = content
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { $0.hasPrefix("- ") }
                .prefix(6)

            if !bullets.isEmpty {
                return bullets.joined(separator: "\n")
            }
        }

        return "No recent memory context available."
    }

    private func summarizeEvents(on date: Date) -> String {
        let events = events(on: date)
        guard !events.isEmpty else { return "No calendar events." }

        return events.prefix(8).map { event in
            let location = event.location?.isEmpty == false ? " @ \(event.location!)" : ""
            return "- \(event.timeString) \(event.title)\(location)"
        }
        .joined(separator: "\n")
    }

    private func events(on date: Date) -> [CalendarEvent] {
        let calendar = Calendar.current
        return calendarService.events.filter { event in
            calendar.isDate(event.startTime, inSameDayAs: date)
        }
        .sorted { $0.startTime < $1.startTime }
    }
}
