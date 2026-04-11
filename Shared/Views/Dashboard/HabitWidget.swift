import SwiftUI

struct HabitWidget: View {
    @Binding var habits: [Habit]

    @Environment(\.theme) private var theme

    private var doneCount: Int { habits.filter(\.isDoneToday).count }

    var body: some View {
        WidgetShell(
            title: "HABITS.SYS",
            badge: "\(doneCount)/\(habits.count)",
            zone: "primary"
        ) {
            VStack(spacing: 10) {
                ForEach($habits) { $habit in
                    Button {
                        habit.isDoneToday.toggle()
                    } label: {
                        HStack(spacing: 10) {
                            Circle()
                                .fill(habit.isDoneToday ? ThemeManager.success : Color.clear)
                                .overlay(
                                    Circle().strokeBorder(
                                        habit.isDoneToday ? ThemeManager.success : ThemeManager.textSecondary,
                                        lineWidth: 1.5
                                    )
                                )
                                .frame(width: 14, height: 14)

                            Text(habit.name)
                                .font(.system(size: theme.fontSize, design: .monospaced))
                                .foregroundColor(habit.isDoneToday ? ThemeManager.textSecondary : ThemeManager.textPrimary)
                                .strikethrough(habit.isDoneToday, color: ThemeManager.textSecondary)
                                .opacity(habit.isDoneToday ? 0.5 : 1)

                            Spacer()
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}
