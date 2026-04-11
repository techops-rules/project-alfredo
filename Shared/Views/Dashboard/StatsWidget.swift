import SwiftUI

struct StatCard: Identifiable {
    let id = UUID()
    let value: String
    let label: String
    let subtitle: String
}

struct StatsWidget: View {
    @Environment(\.theme) private var theme

    let stats: [StatCard] = [
        StatCard(value: "3.2", label: "FOCUS HRS", subtitle: "today"),
        StatCard(value: "12", label: "TASKS DONE", subtitle: "this week"),
        StatCard(value: "4/5", label: "HABITS", subtitle: "today"),
        StatCard(value: "87%", label: "COMPLETION", subtitle: "this week"),
        StatCard(value: "2.1", label: "AVG FOCUS", subtitle: "per day"),
        StatCard(value: "18", label: "CAPTURED", subtitle: "scratchpad"),
    ]

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 3)

    var body: some View {
        WidgetShell(title: "STATS.LOG", zone: "bottom") {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(stats) { stat in
                    VStack(spacing: 4) {
                        Text(stat.value)
                            .font(.system(size: 22, weight: .bold, design: .monospaced))
                            .foregroundColor(ThemeManager.textEmphasis)
                        Text(stat.label)
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundColor(ThemeManager.textSecondary)
                            .tracking(1)
                        Text(stat.subtitle)
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(ThemeManager.textSecondary.opacity(0.6))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
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
