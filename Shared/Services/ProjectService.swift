import Foundation

@MainActor
@Observable
final class ProjectService {
    static let shared = ProjectService()

    private(set) var projects: [Project] = []

    var activeProjects: [Project] {
        projects.filter { $0.status == .active || $0.status == .paused }
    }

    var suggestedProjects: [Project] {
        projects.filter { $0.status == .suggested }
    }

    var suggestedCount: Int { suggestedProjects.count }

    private let saveKey = "projects.data"
    private init() {
        load()
        if projects.isEmpty {
            // Seed with default projects
            projects = [
                Project(name: "alfredo", percent: 15, status: .active, target: "May 2026"),
                Project(name: "Quote Tool v2", percent: 80, status: .active, target: "Apr 2026"),
                Project(name: "Home Lab", percent: 5, status: .paused, target: "TBD"),
            ]
            save()
        }
    }

    func approve(_ project: Project) {
        guard let idx = projects.firstIndex(where: { $0.id == project.id }) else { return }
        projects[idx].status = .active
        projects[idx].suggestedByAlfredo = false
        save()
    }

    func dismiss(_ project: Project) {
        projects.removeAll { $0.id == project.id }
        save()
    }

    func addProject(_ project: Project) {
        projects.append(project)
        save()
    }

    func updateProject(_ project: Project) {
        guard let idx = projects.firstIndex(where: { $0.id == project.id }) else { return }
        projects[idx] = project
        save()
    }

    func addSubtask(to projectId: UUID, text: String) {
        guard let idx = projects.firstIndex(where: { $0.id == projectId }) else { return }
        projects[idx].subtasks.append(Subtask(text: text))
        save()
    }

    func toggleSubtask(projectId: UUID, subtaskId: UUID) {
        guard let pIdx = projects.firstIndex(where: { $0.id == projectId }),
              let sIdx = projects[pIdx].subtasks.firstIndex(where: { $0.id == subtaskId })
        else { return }
        projects[pIdx].subtasks[sIdx].isDone.toggle()
        // Recalculate percent
        let total = projects[pIdx].subtasks.count
        let done = projects[pIdx].subtasks.filter(\.isDone).count
        projects[pIdx].percent = total > 0 ? (done * 100) / total : 0
        save()
    }

    func addNote(to projectId: UUID, text: String) {
        guard let idx = projects.firstIndex(where: { $0.id == projectId }) else { return }
        projects[idx].notes.append(ProjectNote(text: text))
        save()
    }

    // MARK: - Persistence

    private func save() {
        guard let data = try? JSONEncoder().encode(projects) else { return }
        UserDefaults.standard.set(data, forKey: saveKey)
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: saveKey),
              let decoded = try? JSONDecoder().decode([Project].self, from: data)
        else { return }
        projects = decoded
    }
}
