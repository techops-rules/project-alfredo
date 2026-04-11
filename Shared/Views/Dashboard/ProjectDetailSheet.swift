import SwiftUI

struct ProjectDetailSheet: View {
    let project: Project
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    @State private var newSubtaskText = ""
    @State private var newNoteText = ""

    private let projectService = ProjectService.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Header
                header

                Divider().background(theme.accentBorder.opacity(0.3))

                // Progress
                progressSection

                Divider().background(theme.accentBorder.opacity(0.3))

                // Subtasks
                subtasksSection

                Divider().background(theme.accentBorder.opacity(0.3))

                // Notes
                notesSection

                // Suggested projects (if any)
                if !projectService.suggestedProjects.isEmpty {
                    Divider().background(theme.accentBorder.opacity(0.3))
                    suggestedSection
                }
            }
            .padding(16)
        }
        .background(ThemeManager.background)
        #if os(iOS)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        #endif
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(project.name.uppercased())
                    .font(.system(size: 16, weight: .bold, design: .monospaced))
                    .foregroundColor(ThemeManager.textEmphasis)
                    .tracking(2)

                HStack(spacing: 8) {
                    Text(project.status.rawValue.uppercased())
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(statusColor(project.status))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(statusColor(project.status).opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 3))

                    Text("TARGET: \(project.target)")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(ThemeManager.textSecondary)
                }
            }

            Spacer()

            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12))
                    .foregroundColor(ThemeManager.textSecondary)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Progress

    private var progressSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("PROGRESS")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(theme.accentFull)
                    .tracking(1)
                Spacer()
                Text("\(project.percent)%")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundColor(ThemeManager.textEmphasis)
            }

            // ASCII progress bar
            let filled = project.percent / 5
            let empty = 20 - filled
            Text("[" + String(repeating: "█", count: max(0, filled)) + String(repeating: "░", count: max(0, empty)) + "]")
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(theme.accentFull)
        }
    }

    // MARK: - Subtasks

    private var subtasksSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("SUBTASKS")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(theme.accentFull)
                    .tracking(1)

                Spacer()

                let done = project.subtasks.filter(\.isDone).count
                if !project.subtasks.isEmpty {
                    Text("\(done)/\(project.subtasks.count)")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(ThemeManager.textSecondary)
                }
            }

            ForEach(project.subtasks) { subtask in
                HStack(spacing: 8) {
                    Button {
                        projectService.toggleSubtask(projectId: project.id, subtaskId: subtask.id)
                    } label: {
                        Text(subtask.isDone ? "[x]" : "[ ]")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(subtask.isDone ? ThemeManager.success : ThemeManager.textSecondary)
                    }
                    .buttonStyle(.plain)

                    Text(subtask.text)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(subtask.isDone ? ThemeManager.textSecondary.opacity(0.5) : ThemeManager.textPrimary)
                        .strikethrough(subtask.isDone)
                }
            }

            // Add subtask input
            HStack(spacing: 6) {
                Text("+")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(theme.accentFull.opacity(0.5))

                TextField("add subtask...", text: $newSubtaskText)
                    .font(.system(size: 11, design: .monospaced))
                    .textFieldStyle(.plain)
                    .foregroundColor(ThemeManager.textPrimary)
                    .onSubmit {
                        let text = newSubtaskText.trimmingCharacters(in: .whitespaces)
                        guard !text.isEmpty else { return }
                        projectService.addSubtask(to: project.id, text: text)
                        newSubtaskText = ""
                    }
            }
            .padding(.top, 4)
        }
    }

    // MARK: - Notes

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("NOTES")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(theme.accentFull)
                .tracking(1)

            ForEach(project.notes) { note in
                VStack(alignment: .leading, spacing: 2) {
                    Text(note.text)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(ThemeManager.textPrimary)

                    Text(noteTimestamp(note.timestamp))
                        .font(.system(size: 8, design: .monospaced))
                        .foregroundColor(ThemeManager.textSecondary.opacity(0.5))
                }
                .padding(.vertical, 2)
            }

            // Add note input
            HStack(spacing: 6) {
                Text("+")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(theme.accentFull.opacity(0.5))

                TextField("add note...", text: $newNoteText)
                    .font(.system(size: 11, design: .monospaced))
                    .textFieldStyle(.plain)
                    .foregroundColor(ThemeManager.textPrimary)
                    .onSubmit {
                        let text = newNoteText.trimmingCharacters(in: .whitespaces)
                        guard !text.isEmpty else { return }
                        projectService.addNote(to: project.id, text: text)
                        newNoteText = ""
                    }
            }
            .padding(.top, 4)
        }
    }

    // MARK: - Suggested Projects

    private var suggestedSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("ALFREDO SUGGESTS")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(theme.accentFull)
                    .tracking(1)

                Circle()
                    .fill(theme.accentFull)
                    .frame(width: 6, height: 6)
            }

            ForEach(projectService.suggestedProjects) { suggested in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(suggested.name)
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundColor(ThemeManager.textPrimary)
                        Text(suggested.target)
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(ThemeManager.textSecondary)
                    }

                    Spacer()

                    Button {
                        projectService.approve(suggested)
                    } label: {
                        Text("ADD")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundColor(ThemeManager.success)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(ThemeManager.success.opacity(0.15))
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                    }
                    .buttonStyle(.plain)

                    Button {
                        projectService.dismiss(suggested)
                    } label: {
                        Text("X")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundColor(ThemeManager.textSecondary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Helpers

    private func statusColor(_ status: ProjectStatus) -> Color {
        switch status {
        case .active:    return ThemeManager.success
        case .paused:    return ThemeManager.warning
        case .completed: return ThemeManager.textSecondary
        case .suggested: return ThemeManager.shared.accentFull
        }
    }

    private func noteTimestamp(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "MMM d, h:mm a"
        return f.string(from: date)
    }
}
