import SwiftUI

struct TaskBriefingSheet: View {
    let task: AppTask
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    @State private var contextSources: [ContextSource] = []
    @State private var isLoading = true
    @State private var overallConfidence: Double = 0

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().background(ThemeManager.textSecondary.opacity(0.2))

            if isLoading {
                loadingView
            } else {
                briefingContent
            }
        }
        .background(ThemeManager.background)
        .task {
            await gatherContext()
            isLoading = false
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("TASK CONTEXT")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(ThemeManager.textSecondary)
                    .tracking(2)

                Text(task.displayText)
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundColor(ThemeManager.textPrimary)

                HStack(spacing: 8) {
                    Text(task.section.displayName)
                    Text("·")
                    Text("@\(task.scope.rawValue)")
                    if task.isUrgent {
                        Text("·")
                        Text("urgent!")
                            .foregroundColor(ThemeManager.danger)
                    }
                    if let person = task.waitingPerson {
                        Text("·")
                        Text("waiting: \(person)")
                    }
                }
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(ThemeManager.textSecondary)
            }

            Spacer()

            if !isLoading {
                ConfidenceBadge(score: overallConfidence)
            }
        }
        .padding(16)
    }

    // MARK: - Loading

    private var loadingView: some View {
        VStack(spacing: 12) {
            Spacer()
            ProgressView()
                .tint(theme.accentFull)
            Text("gathering context...")
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(ThemeManager.textSecondary)
            Spacer()
        }
    }

    // MARK: - Content

    private var briefingContent: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if contextSources.isEmpty {
                        Text("No related context found.")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(ThemeManager.textSecondary)
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("RELATED CONTEXT")
                                .font(.system(size: 8, weight: .bold, design: .monospaced))
                                .foregroundColor(ThemeManager.textSecondary)
                                .tracking(1.5)

                            ForEach(contextSources) { source in
                                ContextSourceRow(source: source)
                            }
                        }
                    }

                    if overallConfidence < 0.4 {
                        Text("Low confidence -- limited context found.")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(ThemeManager.warning)
                            .padding(8)
                            .background(ThemeManager.warning.opacity(0.1))
                            .cornerRadius(4)
                    }

                    Spacer(minLength: 8)
                }
                .padding(16)
            }

            // Actions
            HStack(spacing: 12) {
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Text("Dismiss")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(ThemeManager.textSecondary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
            }
            .padding(16)
        }
    }

    // MARK: - Context Gathering

    private func gatherContext() async {
        var sources: [ContextSource] = []
        let keywords = extractKeywords()

        // Search calendar events for keyword matches
        let calEvents = CalendarService.shared.events
        for event in calEvents {
            let text = event.title.lowercased()
            for keyword in keywords where text.contains(keyword) {
                sources.append(ContextSource(
                    title: "Meeting: \(event.title)",
                    snippet: "\(event.timeString) · \(event.attendeeNames?.joined(separator: ", ") ?? "")",
                    sourceType: .calendarNotes,
                    url: nil,
                    confidence: 0.7,
                    timestamp: event.startTime
                ))
                break
            }
        }

        // Search memory files
        let memoryPaths = [
            iCloudService.shared.memoryURL,
            URL(fileURLWithPath: NSHomeDirectory())
                .appendingPathComponent(".claude/projects/-Users-todd-Projects-project-alfredo/memory/MEMORY.md")
        ]

        for path in memoryPaths {
            guard let content = try? String(contentsOf: path, encoding: .utf8) else { continue }
            for line in content.components(separatedBy: .newlines) {
                let lower = line.lowercased()
                for keyword in keywords where lower.contains(keyword) && line.count > 5 {
                    sources.append(ContextSource(
                        title: "Memory",
                        snippet: String(line.prefix(150)),
                        sourceType: .memory,
                        url: path,
                        confidence: 0.6,
                        timestamp: Date()
                    ))
                    break
                }
            }
        }

        sources.sort { $0.confidence > $1.confidence }
        contextSources = Array(sources.prefix(5))

        let top = Array(contextSources.prefix(5))
        overallConfidence = top.isEmpty ? 0.0 :
            top.reduce(0.0) { $0 + $1.confidence } / Double(top.count)
    }

    private func extractKeywords() -> [String] {
        let stopWords: Set = ["the", "a", "an", "and", "or", "for", "with", "in", "on", "at", "to"]
        return task.displayText.lowercased()
            .components(separatedBy: .alphanumerics.inverted)
            .filter { $0.count > 2 && !stopWords.contains($0) }
    }
}
