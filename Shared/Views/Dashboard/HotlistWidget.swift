import SwiftUI

struct HotlistWidget: View {
    let tasks: [AppTask]
    let events: [CalendarEvent]
    let onToggle: (AppTask) -> Void

    @Environment(\.theme) private var theme
    @Environment(\.widgetMetrics) private var metrics

    private var items: [HotlistItem] {
        let now = Date()
        let taskItems = tasks
            .filter { $0.isUrgent && $0.section == .today }
            .map { HotlistItem.task($0) }

        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        guard let tomorrow = cal.date(byAdding: .day, value: 1, to: today) else {
            return taskItems
        }
        let eventItems = events
            .filter { !$0.isAllDay && $0.startTime >= today && $0.startTime < tomorrow }
            .map { HotlistItem.event($0) }

        return (taskItems + eventItems).sorted { a, b in
            let aTier = a.sortTier
            let bTier = b.sortTier
            if aTier != bTier { return aTier < bTier }
            return a.sortTime < b.sortTime
        }
    }

    var body: some View {
        let allItems = items
        WidgetShell(
            title: "HOTLIST.EXE",
            badge: allItems.isEmpty ? nil : "\(allItems.count)",
            zone: "urgent"
        ) {
            if allItems.isEmpty {
                VStack {
                    Text("nothing urgent right now")
                        .font(.system(size: metrics.bodyFontSize, design: .monospaced))
                        .foregroundColor(ThemeManager.textSecondary)
                        .opacity(0.5)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Spacer()
                }
                .frame(maxHeight: .infinity)
            } else {
                VStack(alignment: .leading, spacing: metrics.rowSpacing) {
                    ForEach(Array(allItems.prefix(metrics.primaryListLimit))) { item in
                        HotlistRow(item: item, onToggle: onToggle)
                    }
                    if allItems.count > metrics.primaryListLimit {
                        Text("+ \(allItems.count - metrics.primaryListLimit) more urgent items")
                            .font(.system(size: metrics.captionFontSize, design: .monospaced))
                            .foregroundColor(ThemeManager.textSecondary)
                    }
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
    }
}

enum HotlistItem: Identifiable {
    case task(AppTask)
    case event(CalendarEvent)

    var id: String {
        switch self {
        case .task(let t): return "t-\(t.id)"
        case .event(let e): return "e-\(e.id)"
        }
    }

    var sortTier: Int {
        switch self {
        case .task: return 0
        case .event: return 1
        }
    }

    var sortTime: Date {
        switch self {
        case .task: return .distantPast
        case .event(let e): return e.startTime
        }
    }
}

struct HotlistRow: View {
    let item: HotlistItem
    let onToggle: (AppTask) -> Void
    @Environment(\.theme) private var theme
    @Environment(\.widgetMetrics) private var metrics

    var body: some View {
        HStack(spacing: metrics.isCompact ? 6 : 8) {
            urgencyDot

            switch item {
            case .task(let task):
                Text(task.displayText)
                    .font(.system(size: metrics.bodyFontSize, design: .monospaced))
                    .foregroundColor(task.isDone ? ThemeManager.textSecondary : ThemeManager.textPrimary)
                    .strikethrough(task.isDone)
                    .opacity(task.isDone ? 0.28 : 1)
                    .lineLimit(1)
                    .onTapGesture { onToggle(task) }

            case .event(let event):
                Text(event.title)
                    .font(.system(size: metrics.bodyFontSize, design: .monospaced))
                    .foregroundColor(ThemeManager.textPrimary)
                    .lineLimit(1)
                    .opacity(event.isPast ? 0.38 : 1)
            }

            Spacer(minLength: 0)

            switch item {
            case .task:
                if !metrics.isCompact {
                    Text("Today")
                        .font(.system(size: metrics.captionFontSize, design: .monospaced))
                        .foregroundColor(ThemeManager.textSecondary)
                }
            case .event(let event):
                Text(event.timeString)
                    .font(.system(size: metrics.captionFontSize, design: .monospaced))
                    .foregroundColor(ThemeManager.textSecondary)
            }
        }
    }

    @ViewBuilder
    private var urgencyDot: some View {
        switch item {
        case .task(let task):
            let dotSize: CGFloat = metrics.isCompact ? 6 : 8
            Circle()
                .fill(theme.accentFull)
                .frame(width: dotSize, height: dotSize)
                .shadow(color: task.isDone ? .clear : theme.accentFull.opacity(0.5), radius: 3)
        case .event:
            let dotSize: CGFloat = metrics.isCompact ? 6 : 8
            Circle()
                .strokeBorder(theme.accentFull, lineWidth: 1.5)
                .frame(width: dotSize, height: dotSize)
                .opacity(0.6)
        }
    }
}
