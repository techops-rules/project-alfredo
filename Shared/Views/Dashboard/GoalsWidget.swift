import SwiftUI

struct GoalsWidget: View {
    let goals: [Goal]

    @Environment(\.theme) private var theme

    var body: some View {
        WidgetShell(title: "GOALS.SYS", badge: "\(goals.count)", zone: "right") {
            VStack(spacing: 12) {
                ForEach(goals) { goal in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(goal.name)
                                .font(.system(size: theme.fontSize, weight: .medium, design: .monospaced))
                                .foregroundColor(ThemeManager.textPrimary)
                            Spacer()
                            Text(goal.targetDate)
                                .font(.system(size: theme.fontSize - 2, design: .monospaced))
                                .foregroundColor(ThemeManager.textSecondary)
                        }

                        // Progress bar
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
                            .font(.system(size: theme.fontSize - 2, design: .monospaced))
                            .foregroundColor(ThemeManager.textSecondary)
                    }
                }
            }
        }
    }
}
