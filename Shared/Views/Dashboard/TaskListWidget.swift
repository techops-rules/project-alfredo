import SwiftUI

struct TaskListWidget: View {
    let title: String
    let tasks: [AppTask]
    let onToggle: (AppTask) -> Void
    let onToggleSubtask: (Subtask) -> Void
    let onTapTask: (AppTask) -> Void  // focus mode (long-press)
    let onNavigate: (AppTask) -> Void // triple-tap deep link

    @Environment(\.theme) private var theme
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
            if tasks.isEmpty {
                Text("No tasks")
                    .font(.system(size: theme.fontSize, design: .monospaced))
                    .foregroundColor(ThemeManager.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(spacing: 8) {
                    ForEach(tasks) { task in
                        TodoItemView(
                            task: task,
                            onToggle: { onToggle(task) },
                            onToggleSubtask: { onToggleSubtask($0) },
                            onTapText: { selectedTask = task },
                            onLongPress: { onTapTask(task) },
                            onNavigate: { onNavigate($0) }
                        )
                    }

                    // 5-item soft cap warning (ADHD principle)
                    if undoneCount > 5 {
                        Text("You have \(undoneCount) items today. Want to bump some to Soon?")
                            .font(.system(size: theme.fontSize - 2, design: .monospaced))
                            .foregroundColor(ThemeManager.warning)
                            .padding(.top, 4)
                    }
                }
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
