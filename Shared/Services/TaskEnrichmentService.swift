import Foundation

/// Background service that enriches work tasks with:
///   1. Subtask suggestions (2-4 brief steps, Claude-generated via Pi bridge)
///   2. Source tagging ([src:email:ID] or [src:event:ID]) by searching Gmail + Calendar
///
/// Runs silently after tasks load. User sees subtasks appear; they can edit/remove/add.
@Observable
final class TaskEnrichmentService {
    static let shared = TaskEnrichmentService()
    private init() {}

    private var enriching: Set<UUID> = []

    private var piHost: String {
        UserDefaults.standard.string(forKey: "terminal.piHost") ?? "pihub.local"
    }
    private var piPort: Int {
        UserDefaults.standard.integer(forKey: "terminal.piPort") == 0
            ? 8420
            : UserDefaults.standard.integer(forKey: "terminal.piPort")
    }
    private var bridgeURL: URL? {
        URL(string: "http://\(piHost):\(piPort)")
    }

    // MARK: - Public

    /// Enrich a batch of work tasks that have no subtasks and no resolved source yet.
    func enrichIfNeeded(_ tasks: [AppTask], taskBoard: TaskBoardService) {
        let candidates = tasks.filter {
            $0.scope == .work
            && !$0.isDone
            && $0.subtasks.isEmpty
            && !enriching.contains($0.id)
        }
        for task in candidates {
            enriching.insert(task.id)
            Task {
                defer { enriching.remove(task.id) }
                await enrich(task, taskBoard: taskBoard)
            }
        }
    }

    // MARK: - Enrich single task

    private func enrich(_ task: AppTask, taskBoard: TaskBoardService) async {
        async let subtasksResult = fetchSubtasks(for: task)
        async let sourceResult = resolveSource(for: task)

        let (subtasks, source) = await (subtasksResult, sourceResult)

        guard !subtasks.isEmpty || source != .manual else { return }

        await MainActor.run {
            // Write subtasks to file
            if !subtasks.isEmpty {
                taskBoard.saveSubtasks(subtasks, for: task)
            }
            // Write source tag if resolved
            if case .manual = source {} else {
                taskBoard.saveSource(source, for: task)
            }
        }
    }

    // MARK: - Subtask generation via Claude bridge

    private func fetchSubtasks(for task: AppTask) async -> [Subtask] {
        guard let bridge = bridgeURL,
              let url = URL(string: "\(bridge)/subtasks") else { return [] }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 15

        let payload: [String: Any] = [
            "task": task.displayText,
            "scope": task.scope.rawValue,
            "maxSubtasks": 4
        ]
        guard let body = try? JSONSerialization.data(withJSONObject: payload) else { return [] }
        request.httpBody = body

        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = json["subtasks"] as? [String]
        else { return [] }

        return items.prefix(4).map { Subtask(text: $0) }
    }

    // MARK: - Source resolution

    private func resolveSource(for task: AppTask) async -> TaskSource {
        // Already tagged
        if case .manual = task.source {} else { return task.source }

        // Try Gmail first
        if let match = await EmailService.shared.searchForTask(task.displayText) {
            return .email(messageId: match.messageId, subject: match.subject)
        }

        // Try Calendar
        if let match = resolveCalendarSource(for: task) {
            return match
        }

        return .manual
    }

    private func resolveCalendarSource(for task: AppTask) -> TaskSource? {
        let keywords = task.displayText
            .lowercased()
            .components(separatedBy: .alphanumerics.inverted)
            .filter { $0.count > 3 }

        let events = CalendarService.shared.events
        for event in events {
            let title = event.title.lowercased()
            let matched = keywords.filter { title.contains($0) }
            if matched.count >= 2 {
                return .calendarEvent(eventId: event.id, title: event.title)
            }
        }
        return nil
    }
}
