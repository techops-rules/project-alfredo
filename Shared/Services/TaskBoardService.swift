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
