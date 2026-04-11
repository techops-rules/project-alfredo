import SwiftUI

struct StatCard: Identifiable {
    let id = UUID()
    let value: String
    let label: String
    let subtitle: String
}

struct StatsWidget: View {
    @Environment(\.theme) private var theme
    @Environment(\.widgetMetrics) private var metrics

    let stats: [StatCard] = [
        StatCard(value: "3.2", label: "FOCUS HRS", subtitle: "today"),
        StatCard(value: "12", label: "TASKS DONE", subtitle: "this week"),
        StatCard(value: "4/5", label: "HABITS", subtitle: "today"),
        StatCard(value: "87%", label: "COMPLETION", subtitle: "this week"),
        StatCard(value: "2.1", label: "AVG FOCUS", subtitle: "per day"),
        StatCard(value: "18", label: "CAPTURED", subtitle: "scratchpad")
    ]

    var body: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: metrics.rowSpacing), count: metrics.gridColumns)

        WidgetShell(title: "STATS.LOG", zone: "bottom") {
            LazyVGrid(columns: columns, spacing: metrics.rowSpacing) {
                ForEach(stats.prefix(max(metrics.gridColumns * 2, 4))) { stat in
                    VStack(spacing: 4) {
                        Text(stat.value)
                            .font(.system(size: metrics.emphasisFontSize, weight: .bold, design: .monospaced))
                            .foregroundColor(ThemeManager.textEmphasis)
                            .minimumScaleFactor(0.75)
                        Text(stat.label)
                            .font(.system(size: metrics.captionFontSize, weight: .medium, design: .monospaced))
                            .foregroundColor(ThemeManager.textSecondary)
                            .tracking(1)
                            .lineLimit(1)
                        if !metrics.isCompact {
                            Text(stat.subtitle)
                                .font(.system(size: metrics.captionFontSize, design: .monospaced))
                                .foregroundColor(ThemeManager.textSecondary.opacity(0.6))
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, metrics.isCompact ? 10 : 12)
                    .background(ThemeManager.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .strokeBorder(theme.accentBorder, lineWidth: 0.5)
                    )
                }
            }
        }
    }
}
