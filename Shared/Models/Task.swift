import Foundation

// MARK: - Subtask

struct Subtask: Identifiable, Codable, Equatable {
    let id: UUID
    var text: String
    var isDone: Bool
    var fileLineIndex: Int?

    init(id: UUID = UUID(), text: String, isDone: Bool = false, fileLineIndex: Int? = nil) {
        self.id = id
        self.text = text
        self.isDone = isDone
        self.fileLineIndex = fileLineIndex
    }
}

// MARK: - TaskSource

enum TaskSource: Codable, Equatable {
    case email(messageId: String, subject: String)
    case calendarEvent(eventId: String, title: String)
    case manual
    case unresolvable

    var isNavigable: Bool {
        switch self {
        case .email, .calendarEvent: return true
        case .manual, .unresolvable: return false
        }
    }
}

// MARK: - TaskSection / Scope

enum TaskSection: String, CaseIterable, Codable {
    case today, soon, later, waiting, deferred, agenda, inbox, done, reference

    var displayName: String {
        rawValue.capitalized
    }

    var markdownHeader: String {
        "## \(displayName)"
    }
}

enum Scope: String, Codable {
    case work, personal
}

struct AppTask: Identifiable, Codable, Equatable {
    let id: UUID
    var text: String
    var isDone: Bool
    var isUrgent: Bool
    var section: TaskSection
    var scope: Scope
    var tags: [String]
    var deferDate: Date?
    var followUpDate: Date?
    var waitingPerson: String?
    var fileLineIndex: Int?
    var subtasks: [Subtask]
    var source: TaskSource

    init(
        id: UUID = UUID(),
        text: String,
        isDone: Bool = false,
        isUrgent: Bool = false,
        section: TaskSection = .inbox,
        scope: Scope = .work,
        tags: [String] = [],
        deferDate: Date? = nil,
        followUpDate: Date? = nil,
        waitingPerson: String? = nil,
        fileLineIndex: Int? = nil,
        subtasks: [Subtask] = [],
        source: TaskSource = .manual
    ) {
        self.id = id
        self.text = text
        self.isDone = isDone
        self.isUrgent = isUrgent
        self.section = section
        self.scope = scope
        self.tags = tags
        self.deferDate = deferDate
        self.followUpDate = followUpDate
        self.waitingPerson = waitingPerson
        self.fileLineIndex = fileLineIndex
        self.subtasks = subtasks
        self.source = source
    }

    var subtasksDoneCount: Int { subtasks.filter(\.isDone).count }
    var hasSubtasks: Bool { !subtasks.isEmpty }

    var displayText: String {
        var t = text
        // Strip tags for display
        t = t.replacingOccurrences(of: " @work", with: "")
        t = t.replacingOccurrences(of: " @personal", with: "")
        if t.hasSuffix(" !") { t = String(t.dropLast(2)) }
        return t.trimmingCharacters(in: .whitespaces)
    }
}
