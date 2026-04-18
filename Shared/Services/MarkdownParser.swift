import Foundation

struct MarkdownParser {
    // MARK: - Date Parsing

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMddyy"
        return f
    }()

    // MARK: - Task Board Parsing

    static func parseTaskBoard(_ content: String) -> [AppTask] {
        var tasks: [AppTask] = []
        var currentSection: TaskSection?
        let lines = content.components(separatedBy: "\n")

        for (index, line) in lines.enumerated() {
            // Indented subtask (2+ spaces or tab prefix) — attach to last task
            let isIndented = line.hasPrefix("  ") || line.hasPrefix("\t")
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if isIndented, trimmed.hasPrefix("- ["), !tasks.isEmpty {
                let isDone = trimmed.hasPrefix("- [x]") || trimmed.hasPrefix("- [X]")
                let text = String(trimmed.dropFirst(6)).trimmingCharacters(in: .whitespaces)
                guard !text.isEmpty else { continue }
                if tasks[tasks.count - 1].subtasks.count < 5 {
                    tasks[tasks.count - 1].subtasks.append(
                        Subtask(text: text, isDone: isDone, fileLineIndex: index)
                    )
                }
                continue
            }

            // Detect section headers
            if trimmed.hasPrefix("## ") {
                let sectionName = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                currentSection = TaskSection.allCases.first {
                    $0.displayName.lowercased() == sectionName.lowercased()
                }
                continue
            }

            guard let section = currentSection else { continue }

            // Parse checkbox lines (Today/Done sections)
            if trimmed.hasPrefix("- [") {
                let isDone = trimmed.hasPrefix("- [x]") || trimmed.hasPrefix("- [X]")
                let rawText = String(trimmed.dropFirst(6)).trimmingCharacters(in: .whitespaces)
                if rawText.isEmpty || rawText == "-" { continue }

                let source = parseSource(from: rawText)
                let text = stripSourceTag(from: rawText)
                let isUrgent = text.hasSuffix("!")
                let scope = parseScope(from: text)
                let tags = parseTags(from: text)
                let deferDate = parseDate(from: text, prefix: "defer:")
                let followUp = parseDate(from: text, prefix: "follow-up:")

                tasks.append(AppTask(
                    text: text,
                    isDone: isDone,
                    isUrgent: isUrgent,
                    section: section,
                    scope: scope,
                    tags: tags,
                    deferDate: deferDate,
                    followUpDate: followUp,
                    fileLineIndex: index,
                    source: source
                ))
            }
            // Parse plain list items (non-Today sections)
            else if trimmed.hasPrefix("- ") && !trimmed.hasPrefix("- [") {
                let rawText = String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                if rawText.isEmpty || rawText == "-" { continue }

                let source = parseSource(from: rawText)
                let text = stripSourceTag(from: rawText)

                var waitingPerson: String?
                if section == .waiting, let match = text.range(of: #"^\[(.+?)\]"#, options: .regularExpression) {
                    waitingPerson = String(text[match]).replacingOccurrences(of: "[", with: "").replacingOccurrences(of: "]", with: "")
                }

                let scope = parseScope(from: text)
                let tags = parseTags(from: text)

                tasks.append(AppTask(
                    text: text,
                    isDone: false,
                    isUrgent: text.hasSuffix("!"),
                    section: section,
                    scope: scope,
                    tags: tags,
                    waitingPerson: waitingPerson,
                    fileLineIndex: index,
                    source: source
                ))
            }
        }

        return tasks
    }

    // MARK: - Task Board Writing

    static func toggleTask(in content: String, at lineIndex: Int) -> String {
        var lines = content.components(separatedBy: "\n")
        guard lineIndex < lines.count else { return content }

        let line = lines[lineIndex]
        if line.contains("- [ ]") {
            lines[lineIndex] = line.replacingOccurrences(of: "- [ ]", with: "- [x]")
        } else if line.contains("- [x]") || line.contains("- [X]") {
            lines[lineIndex] = line.replacingOccurrences(of: "- [x]", with: "- [ ]")
            lines[lineIndex] = lines[lineIndex].replacingOccurrences(of: "- [X]", with: "- [ ]")
        }

        return lines.joined(separator: "\n")
    }

    /// Toggle a subtask — same mechanism, works for indented lines too
    static func toggleSubtask(in content: String, at lineIndex: Int) -> String {
        toggleTask(in: content, at: lineIndex)
    }

    /// Append subtasks to a task line in the file (inserts after the task's fileLineIndex)
    static func writeSubtasks(_ subtasks: [Subtask], in content: String, afterLine lineIndex: Int) -> String {
        var lines = content.components(separatedBy: "\n")
        guard lineIndex < lines.count else { return content }

        // Remove any existing indented subtask lines right after the parent
        var insertAt = lineIndex + 1
        while insertAt < lines.count {
            let l = lines[insertAt]
            if l.hasPrefix("  ") || l.hasPrefix("\t") {
                lines.remove(at: insertAt)
            } else {
                break
            }
        }

        // Insert new subtasks
        let subtaskLines = subtasks.map { sub in
            "  - [\(sub.isDone ? "x" : " ")] \(sub.text)"
        }
        lines.insert(contentsOf: subtaskLines, at: insertAt)

        return lines.joined(separator: "\n")
    }

    // MARK: - Scratchpad Parsing

    static func parseScratchpad(_ content: String) -> ScratchpadFile {
        let lines = content.components(separatedBy: "\n")
        guard let sepIndex = lines.firstIndex(of: "---") else {
            return ScratchpadFile(lines: [])
        }
        let contentLines = lines[(sepIndex + 1)...]
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return ScratchpadFile(lines: Array(contentLines))
    }

    static func appendToScratchpad(_ content: String, line: String) -> String {
        var result = content
        if !result.hasSuffix("\n") { result += "\n" }
        result += line + "\n"
        return result
    }

    // MARK: - Memory Parsing

    static func parseMemory(_ content: String) -> MemoryFile {
        var memory = MemoryFile()
        var currentSection: String?
        let lines = content.components(separatedBy: "\n")

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("## ") {
                currentSection = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                continue
            }

            if trimmed.hasPrefix("- ") {
                let item = String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                if item.isEmpty { continue }

                switch currentSection {
                case "Now":                memory.now.append(item)
                case "Open Threads":       memory.openThreads.append(item)
                case "Parked":             memory.parked.append(item)
                case "People & Context":   memory.peopleAndContext.append(item)
                case "Recent Decisions":   memory.recentDecisions.append(item)
                default: break
                }
            }
        }

        return memory
    }

    // MARK: - Habits Parsing

    static func parseHabits(_ content: String) -> [Habit] {
        let lines = content.components(separatedBy: "\n")
        return lines.compactMap { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("- ") else { return nil }
            let name = String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else { return nil }
            return Habit(name: name)
        }
    }

    // MARK: - Goals Parsing

    static func parseGoals(_ content: String) -> [Goal] {
        let lines = content.components(separatedBy: "\n")
        return lines.compactMap { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("- ") else { return nil }
            let parts = String(trimmed.dropFirst(2)).components(separatedBy: " | ")
            guard parts.count >= 3 else { return nil }
            let name = parts[0].trimmingCharacters(in: .whitespaces)
            let target = parts[1].trimmingCharacters(in: .whitespaces)
            let pctStr = parts[2].trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "%", with: "")
            let pct = Int(pctStr) ?? 0
            return Goal(name: name, targetDate: target, progressPercent: pct, category: .sideProject)
        }
    }

    // MARK: - Helpers

    private static func parseScope(from text: String) -> Scope {
        if text.contains("@personal") { return .personal }
        return .work
    }

    private static func parseTags(from text: String) -> [String] {
        let pattern = #"[#@]\w+"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            guard let r = Range(match.range, in: text) else { return nil }
            return String(text[r])
        }
    }

    /// Parses [src:email:ID:Subject] or [src:event:ID:Title] tags
    static func parseSource(from text: String) -> TaskSource {
        let emailPattern = #"\[src:email:([^:]+):([^\]]+)\]"#
        let eventPattern = #"\[src:event:([^:]+):([^\]]+)\]"#

        if let regex = try? NSRegularExpression(pattern: emailPattern),
           let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
           let idRange = Range(match.range(at: 1), in: text),
           let subjectRange = Range(match.range(at: 2), in: text) {
            return .email(messageId: String(text[idRange]), subject: String(text[subjectRange]))
        }

        if let regex = try? NSRegularExpression(pattern: eventPattern),
           let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
           let idRange = Range(match.range(at: 1), in: text),
           let titleRange = Range(match.range(at: 2), in: text) {
            return .calendarEvent(eventId: String(text[idRange]), title: String(text[titleRange]))
        }

        return .manual
    }

    static func stripSourceTag(from text: String) -> String {
        var result = text
        let patterns = [#"\[src:email:[^\]]+\]"#, #"\[src:event:[^\]]+\]"#]
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern) {
                let range = NSRange(result.startIndex..., in: result)
                result = regex.stringByReplacingMatches(in: result, range: range, withTemplate: "")
            }
        }
        return result.trimmingCharacters(in: .whitespaces)
    }

    /// Encode a TaskSource back to its markdown tag
    static func sourceTag(for source: TaskSource) -> String {
        switch source {
        case .email(let id, let subject):
            return " [src:email:\(id):\(subject)]"
        case .calendarEvent(let id, let title):
            return " [src:event:\(id):\(title)]"
        case .manual, .unresolvable:
            return ""
        }
    }

    private static func parseDate(from text: String, prefix: String) -> Date? {
        let pattern = "\\[\(prefix)(\\d{6})\\]"
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let dateRange = Range(match.range(at: 1), in: text)
        else { return nil }
        return dateFormatter.date(from: String(text[dateRange]))
    }
}
