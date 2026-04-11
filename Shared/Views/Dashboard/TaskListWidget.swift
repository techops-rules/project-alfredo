import SwiftUI

struct TaskListWidget: View {
    let title: String
    let tasks: [AppTask]
    let onToggle: (AppTask) -> Void
    let onTapTask: (AppTask) -> Void

    @Environment(\.theme) private var theme

    private var undoneCount: Int {
        tasks.filter { !$0.isDone }.count
    }

    var body: some View {
        WidgetShell(
            title: title,
            badge: undoneCount > 0 ? "\(undoneCount) open" : nil,
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
                        TodoItemView(task: task, onToggle: { onToggle(task) })
                            .onTapGesture { onTapTask(task) }
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
    }
}
