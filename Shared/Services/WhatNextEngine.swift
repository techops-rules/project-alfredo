import Foundation

@Observable
final class WhatNextEngine {
    var currentTask: AppTask?
    var startedAt: Date?
    private var skipSet: Set<UUID> = []

    var elapsedMinutes: Int {
        guard let start = startedAt else { return 0 }
        return Int(Date().timeIntervalSince(start) / 60)
    }

    var elapsedString: String {
        let mins = elapsedMinutes
        if mins < 60 { return "\(mins) min" }
        let hrs = mins / 60
        let rem = mins % 60
        return "\(hrs) hr \(rem) min"
    }

    func suggestNext(from tasks: [AppTask]) -> AppTask? {
        let candidates = tasks
            .filter { !$0.isDone && $0.section == .today && !skipSet.contains($0.id) }

        let sorted = candidates.sorted { a, b in
            // 1. Deferred date has passed
            let aDeferred = a.deferDate.map { $0 <= Date() } ?? false
            let bDeferred = b.deferDate.map { $0 <= Date() } ?? false
            if aDeferred != bDeferred { return aDeferred }

            // 2. Urgent
            if a.isUrgent != b.isUrgent { return a.isUrgent }

            // 3. Fewest words (smallest task)
            let aWords = a.text.split(separator: " ").count
            let bWords = b.text.split(separator: " ").count
            if aWords != bWords { return aWords < bWords }

            // 4. File order
            return (a.fileLineIndex ?? Int.max) < (b.fileLineIndex ?? Int.max)
        }

        return sorted.first
    }

    func startTask(_ task: AppTask) {
        currentTask = task
        startedAt = Date()
        skipSet.removeAll()
    }

    func skip(_ task: AppTask) {
        skipSet.insert(task.id)
    }

    func clearCurrent() {
        currentTask = nil
        startedAt = nil
    }

    func resetSkips() {
        skipSet.removeAll()
    }
}
