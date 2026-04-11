import SwiftUI

struct TodoItemView: View {
    let task: AppTask
    let onToggle: () -> Void
    let onToggleSubtask: (Subtask) -> Void
    var onTapText: (() -> Void)?
    var onLongPress: (() -> Void)?
    var onNavigate: ((AppTask) -> Void)?

    @Environment(\.theme) private var theme
    @Environment(\.widgetMetrics) private var metrics
    @State private var isExpanded = false
    @State private var isFlashing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: metrics.isCompact ? 8 : 10) {
                Button(action: onToggle) {
                    Circle()
                        .fill(task.isDone ? ThemeManager.success : Color.clear)
                        .overlay(
                            Circle().strokeBorder(
                                task.isDone ? ThemeManager.success : ThemeManager.textSecondary,
                                lineWidth: 1.5
                            )
                        )
                        .frame(width: metrics.isCompact ? 12 : 14, height: metrics.isCompact ? 12 : 14)
                }
                .buttonStyle(.plain)

                Text(task.displayText)
                    .font(.system(size: metrics.bodyFontSize, design: .monospaced))
                    .foregroundColor(task.isDone ? ThemeManager.textSecondary : ThemeManager.textPrimary)
                    .strikethrough(task.isDone, color: ThemeManager.textSecondary)
                    .opacity(task.isDone ? 0.5 : 1)
                    .lineLimit(metrics.isCompact ? 1 : 2)
                    .contentShape(Rectangle())
                    .onTapGesture(count: 3) {
                        handleTripleTap()
                    }
                    .onTapGesture(count: 1) {
                        if task.hasSubtasks && !metrics.isCompact {
                            withAnimation(.easeInOut(duration: 0.18)) {
                                isExpanded.toggle()
                            }
                        } else {
                            onTapText?()
                        }
                    }
                    .onLongPressGesture(minimumDuration: 0.5) {
                        onLongPress?()
                    }

                Spacer(minLength: 0)

                if task.hasSubtasks && !isExpanded && !metrics.isCompact {
                    subtaskDots
                }

                if task.hasSubtasks && !metrics.isCompact {
                    Image(systemName: "chevron.right")
                        .font(.system(size: metrics.captionFontSize, weight: .medium))
                        .foregroundColor(ThemeManager.textSecondary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .animation(.easeInOut(duration: 0.18), value: isExpanded)
                }

                if task.isUrgent {
                    Text("!")
                        .font(.system(size: metrics.bodyFontSize, weight: .bold, design: .monospaced))
                        .foregroundColor(ThemeManager.danger)
                }
            }
            .opacity(isFlashing ? 0.25 : 1)

            if isExpanded && task.hasSubtasks {
                VStack(alignment: .leading, spacing: max(4, metrics.rowSpacing - 2)) {
                    ForEach(task.subtasks.prefix(metrics.secondaryListLimit)) { subtask in
                        SubtaskRow(subtask: subtask) {
                            onToggleSubtask(subtask)
                        }
                    }
                }
                .padding(.leading, 24)
                .padding(.top, 6)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private var subtaskDots: some View {
        HStack(spacing: 3) {
            ForEach(Array(task.subtasks.prefix(5).enumerated()), id: \.offset) { _, sub in
                Circle()
                    .fill(sub.isDone ? ThemeManager.success : ThemeManager.textSecondary.opacity(0.4))
                    .frame(width: 5, height: 5)
            }
        }
    }

    private func handleTripleTap() {
        if task.source.isNavigable {
            onNavigate?(task)
        } else {
            flash()
        }
    }

    private func flash() {
        withAnimation(.easeOut(duration: 0.1)) { isFlashing = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            withAnimation(.easeIn(duration: 0.15)) { isFlashing = false }
        }
    }
}

struct SubtaskRow: View {
    let subtask: Subtask
    let onToggle: () -> Void

    @Environment(\.theme) private var theme
    @Environment(\.widgetMetrics) private var metrics

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onToggle) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(subtask.isDone ? ThemeManager.success : Color.clear)
                    .overlay(
                        RoundedRectangle(cornerRadius: 2)
                            .strokeBorder(
                                subtask.isDone ? ThemeManager.success : ThemeManager.textSecondary,
                                lineWidth: 1.2
                            )
                    )
                    .frame(width: 11, height: 11)
            }
            .buttonStyle(.plain)

            Text(subtask.text)
                .font(.system(size: max(9, metrics.bodyFontSize - 1), design: .monospaced))
                .foregroundColor(subtask.isDone ? ThemeManager.textSecondary : ThemeManager.textPrimary.opacity(0.85))
                .strikethrough(subtask.isDone, color: ThemeManager.textSecondary)
                .opacity(subtask.isDone ? 0.5 : 1)
                .lineLimit(metrics.isCompact ? 1 : 2)
        }
    }
}
