import Foundation

@Observable
final class TaskBoardService {
    private let icloud = iCloudService.shared
    private(set) var tasks: [AppTask] = []

    init() {
        reload()
    }

    func reload() {
        guard let content = icloud.readFile(at: icloud.taskBoardURL) else { return }
        tasks = MarkdownParser.parseTaskBoard(content)
    }

    func toggleTask(_ task: AppTask) {
        guard let content = icloud.readFile(at: icloud.taskBoardURL),
              let lineIndex = task.fileLineIndex else { return }
        let updated = MarkdownParser.toggleTask(in: content, at: lineIndex)
        icloud.writeFile(at: icloud.taskBoardURL, content: updated)
        reload()
    }

    func toggleSubtask(_ subtask: Subtask) {
        guard let content = icloud.readFile(at: icloud.taskBoardURL),
              let lineIndex = subtask.fileLineIndex else { return }
        let updated = MarkdownParser.toggleSubtask(in: content, at: lineIndex)
        icloud.writeFile(at: icloud.taskBoardURL, content: updated)
        reload()
    }

    func saveSubtasks(_ subtasks: [Subtask], for task: AppTask) {
        guard let content = icloud.readFile(at: icloud.taskBoardURL),
              let lineIndex = task.fileLineIndex else { return }
        let updated = MarkdownParser.writeSubtasks(subtasks, in: content, afterLine: lineIndex)
        icloud.writeFile(at: icloud.taskBoardURL, content: updated)
        reload()
    }

    func saveSource(_ source: TaskSource, for task: AppTask) {
        guard let content = icloud.readFile(at: icloud.taskBoardURL),
              let lineIndex = task.fileLineIndex else { return }
        var lines = content.components(separatedBy: "\n")
        guard lineIndex < lines.count else { return }
        // Strip existing src tag, append new one
        var line = MarkdownParser.stripSourceTag(from: lines[lineIndex])
        line += MarkdownParser.sourceTag(for: source)
        lines[lineIndex] = line
        icloud.writeFile(at: icloud.taskBoardURL, content: lines.joined(separator: "\n"))
        reload()
    }

    var todayTasks: [AppTask] {
        tasks.filter { $0.section == .today }
    }

    var workTasks: [AppTask] {
        todayTasks.filter { $0.scope == .work }
    }

    var personalTasks: [AppTask] {
        todayTasks.filter { $0.scope == .personal }
    }

    var soonTasks: [AppTask] {
        tasks.filter { $0.section == .soon }
    }

    var laterTasks: [AppTask] {
        tasks.filter { $0.section == .later }
    }

    var doneTasks: [AppTask] {
        todayTasks.filter { $0.isDone }
    }

    var undoneTasks: [AppTask] {
        todayTasks.filter { !$0.isDone }
    }

    var todayDoneCount: Int { doneTasks.count }
    var todayTotalCount: Int { todayTasks.count }
}
