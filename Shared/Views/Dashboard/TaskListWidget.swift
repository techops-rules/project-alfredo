import SwiftUI

struct TaskListWidget: View {
    let title: String
    let tasks: [AppTask]
    let onToggle: (AppTask) -> Void
    let onToggleSubtask: (Subtask) -> Void
    let onTapTask: (AppTask) -> Void
    let onNavigate: (AppTask) -> Void

    @Environment(\.theme) private var theme
    @Environment(\.widgetMetrics) private var inheritedMetrics
    @State private var selectedTask: AppTask?

    private var undoneCount: Int {
        tasks.filter { !$0.isDone }.count
    }

    var body: some View {
        WidgetShell(
            title: title,
            badgeView: tasks.isEmpty ? nil : AnyView(
                ProgressDots(percent: tasks.isEmpty ? 0 : (tasks.count - undoneCount) * 100 / tasks.count)
            ),
            zone: "primary"
        ) {
            let metrics = inheritedMetrics
            let visibleTasks = Array(tasks.prefix(metrics.primaryListLimit))
            let hiddenCount = max(0, tasks.count - visibleTasks.count)

            if tasks.isEmpty {
                Text("No tasks")
                    .font(.system(size: metrics.bodyFontSize, design: .monospaced))
                    .foregroundColor(ThemeManager.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(alignment: .leading, spacing: metrics.rowSpacing) {
                    ForEach(visibleTasks) { task in
                        TodoItemView(
                            task: task,
                            onToggle: { onToggle(task) },
                            onToggleSubtask: { onToggleSubtask($0) },
                            onTapText: { selectedTask = task },
                            onLongPress: { onTapTask(task) },
                            onNavigate: { onNavigate($0) }
                        )
                    }

                    if hiddenCount > 0 {
                        Text("+
\(hiddenCount) more hidden at this size")
                            .font(.system(size: metrics.captionFontSize, design: .monospaced))
                            .foregroundColor(ThemeManager.textSecondary.opacity(0.7))
                    }

                    if undoneCount > 5 && !metrics.isCompact {
                        Text("You have \(undoneCount) items today. Want to bump some to Soon?")
                            .font(.system(size: metrics.captionFontSize, design: .monospaced))
                            .foregroundColor(ThemeManager.warning)
                            .padding(.top, 4)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .sheet(item: $selectedTask) { task in
            TaskBriefingSheet(task: task)
                #if os(iOS)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                #endif
        }
    }
}
