import SwiftUI

struct TodayBarWidget: View {
    let tasksDone: Int
    let tasksTotal: Int
    let habitsDone: Int
    let habitsTotal: Int
    let focusHours: Double
    let eventsLeft: Int

    @Environment(\.theme) private var theme
    @Environment(\.widgetMetrics) private var metrics

    private var statItems: [(String, String)] {
        [
            ("\(tasksDone)/\(tasksTotal)", "TASKS"),
            ("\(habitsDone)/\(habitsTotal)", "HABITS"),
            (String(format: "%.1f", focusHours), "FOCUS HRS"),
            ("\(eventsLeft)", "EVENTS LEFT")
        ]
    }

    var body: some View {
        if metrics.prefersStackedStats {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: metrics.rowSpacing) {
                ForEach(Array(statItems.enumerated()), id: \.offset) { _, item in
                    statItem(value: item.0, label: item.1)
                }
            }
        } else {
            HStack(spacing: 0) {
                ForEach(Array(statItems.enumerated()), id: \.offset) { index, item in
                    statItem(value: item.0, label: item.1)
                    if index < statItems.count - 1 {
                        divider
                    }
                }
            }
        }
    }

    private func statItem(value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: metrics.emphasisFontSize, weight: .bold, design: .monospaced))
                .foregroundColor(ThemeManager.textEmphasis)
                .minimumScaleFactor(0.75)
            Text(label)
                .font(.system(size: metrics.captionFontSize, weight: .medium, design: .monospaced))
                .foregroundColor(ThemeManager.textSecondary)
                .tracking(1)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }

    private var divider: some View {
        Rectangle()
            .fill(ThemeManager.textSecondary.opacity(0.2))
            .frame(width: 1, height: metrics.isCompact ? 28 : 40)
    }
}
