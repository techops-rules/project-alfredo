import SwiftUI

struct TodoItemView: View {
    let task: AppTask
    let onToggle: () -> Void

    @Environment(\.theme) private var theme

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 10) {
                // Circle indicator
                Circle()
                    .fill(task.isDone ? ThemeManager.success : Color.clear)
                    .overlay(
                        Circle().strokeBorder(
                            task.isDone ? ThemeManager.success : ThemeManager.textSecondary,
                            lineWidth: 1.5
                        )
                    )
                    .frame(width: 14, height: 14)

                // Task text
                Text(task.displayText)
                    .font(.system(size: theme.fontSize, design: .monospaced))
                    .foregroundColor(task.isDone ? ThemeManager.textSecondary : ThemeManager.textPrimary)
                    .strikethrough(task.isDone, color: ThemeManager.textSecondary)
                    .opacity(task.isDone ? 0.5 : 1)
                    .lineLimit(2)

                Spacer()

                // Urgency marker
                if task.isUrgent {
                    Text("!")
                        .font(.system(size: theme.fontSize, weight: .bold, design: .monospaced))
                        .foregroundColor(ThemeManager.danger)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
