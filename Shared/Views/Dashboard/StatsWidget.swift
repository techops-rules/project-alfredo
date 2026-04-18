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

    let taskBoard: TaskBoardService?
    let scratchpad: ScratchpadService?
    let habits: [Habit]

    init(taskBoard: TaskBoardService? = nil, scratchpad: ScratchpadService? = nil, habits: [Habit] = []) {
        self.taskBoard = taskBoard
        self.scratchpad = scratchpad
        self.habits = habits
    }

    private var stats: [StatCard] {
        var out: [StatCard] = []
        if let tb = taskBoard {
            let done = tb.todayDoneCount
            let total = tb.todayTotalCount
            out.append(StatCard(value: "\(done)/\(total)", label: "TODAY", subtitle: "tasks done"))
            out.append(StatCard(value: "\(tb.deferredTasks.count)", label: "DEFERRED", subtitle: "parked"))
            out.append(StatCard(value: "\(tb.waitingTasks.count)", label: "WAITING", subtitle: "on others"))
        }
        let habitDone = habits.filter { $0.isDoneToday }.count
        if !habits.isEmpty {
            out.append(StatCard(value: "\(habitDone)/\(habits.count)", label: "HABITS", subtitle: "today"))
        }
        if let sp = scratchpad {
            out.append(StatCard(value: "\(sp.scratchpad.lines.count)", label: "CAPTURED", subtitle: "scratchpad"))
        }
        return out
    }

    var body: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: metrics.rowSpacing), count: metrics.gridColumns)
        let cards = stats

        WidgetShell(title: "STATS.LOG", zone: "bottom") {
            if cards.isEmpty {
                Text("no stats yet — tasks + habits light up once data loads.")
                    .font(.system(size: metrics.captionFontSize, design: .monospaced))
                    .foregroundColor(ThemeManager.textSecondary.opacity(0.65))
                    .italic()
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                LazyVGrid(columns: columns, spacing: metrics.rowSpacing) {
                    ForEach(cards.prefix(max(metrics.gridColumns * 2, 4))) { stat in
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
}
