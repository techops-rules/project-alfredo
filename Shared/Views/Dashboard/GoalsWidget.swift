import SwiftUI

struct GoalsWidget: View {
    let goals: [Goal]

    @Environment(\.theme) private var theme
    @Environment(\.widgetMetrics) private var metrics

    var body: some View {
        WidgetShell(title: "GOALS.SYS", badge: "\(goals.count)", zone: "right") {
            VStack(spacing: metrics.sectionSpacing) {
                ForEach(goals.prefix(metrics.secondaryListLimit)) { goal in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(goal.name)
                                .font(.system(size: metrics.bodyFontSize, weight: .medium, design: .monospaced))
                                .foregroundColor(ThemeManager.textPrimary)
                                .lineLimit(1)
                            Spacer(minLength: 8)
                            if !metrics.isCompact {
                                Text(goal.targetDate)
                                    .font(.system(size: metrics.captionFontSize, design: .monospaced))
                                    .foregroundColor(ThemeManager.textSecondary)
                            }
                        }

                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(theme.accentTrack)
                                    .frame(height: 6)
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(theme.accentFull)
                                    .frame(width: geo.size.width * CGFloat(goal.progressPercent) / 100, height: 6)
                            }
                        }
                        .frame(height: 6)

                        Text("\(goal.progressPercent)%")
                            .font(.system(size: metrics.captionFontSize, design: .monospaced))
                            .foregroundColor(ThemeManager.textSecondary)
                    }
                }

                if goals.count > metrics.secondaryListLimit {
                    Text("+ \(goals.count - metrics.secondaryListLimit) more goals")
                        .font(.system(size: metrics.captionFontSize, design: .monospaced))
                        .foregroundColor(ThemeManager.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }
}
