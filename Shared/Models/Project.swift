import Foundation

enum ProjectStatus: String, Codable, CaseIterable {
    case active, paused, completed, suggested
}

struct Project: Identifiable, Codable {
    let id: UUID
    var name: String
    var percent: Int
    var status: ProjectStatus
    var target: String
    var subtasks: [Subtask]
    var notes: [ProjectNote]
    var suggestedByAlfredo: Bool
    var createdDate: Date

    init(
        id: UUID = UUID(),
        name: String,
        percent: Int = 0,
        status: ProjectStatus = .active,
        target: String = "TBD",
        subtasks: [Subtask] = [],
        notes: [ProjectNote] = [],
        suggestedByAlfredo: Bool = false,
        createdDate: Date = .now
    ) {
        self.id = id
        self.name = name
        self.percent = percent
        self.status = status
        self.target = target
        self.subtasks = subtasks
        self.notes = notes
        self.suggestedByAlfredo = suggestedByAlfredo
        self.createdDate = createdDate
    }
}

struct ProjectNote: Identifiable, Codable {
    let id: UUID
    var text: String
    let timestamp: Date

    init(id: UUID = UUID(), text: String, timestamp: Date = .now) {
        self.id = id
        self.text = text
        self.timestamp = timestamp
    }
}
