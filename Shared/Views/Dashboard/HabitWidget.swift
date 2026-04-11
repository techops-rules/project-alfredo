import SwiftUI

struct HabitWidget: View {
    @Binding var habits: [Habit]

    @Environment(\.theme) private var theme
    @Environment(\.widgetMetrics) private var metrics

    private var doneCount: Int { habits.filter(\.isDoneToday).count }

    var body: some View {
        WidgetShell(
            title: "HABITS.SYS",
            badgeView: habits.isEmpty ? nil : AnyView(
                ProgressDots(percent: habits.isEmpty ? 0 : doneCount * 100 / habits.count)
            ),
            zone: "primary"
        ) {
            VStack(spacing: metrics.rowSpacing) {
                ForEach($habits.prefix(metrics.primaryListLimit)) { $habit in
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
                                .font(.system(size: metrics.bodyFontSize, design: .monospaced))
                                .foregroundColor(habit.isDoneToday ? ThemeManager.textSecondary : ThemeManager.textPrimary)
                                .strikethrough(habit.isDoneToday, color: ThemeManager.textSecondary)
                                .opacity(habit.isDoneToday ? 0.5 : 1)
                                .lineLimit(metrics.isCompact ? 1 : 2)

                            Spacer(minLength: 0)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }

                if habits.count > metrics.primaryListLimit {
                    Text("+ \(habits.count - metrics.primaryListLimit) more habits")
                        .font(.system(size: metrics.captionFontSize, design: .monospaced))
                        .foregroundColor(ThemeManager.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }
}
