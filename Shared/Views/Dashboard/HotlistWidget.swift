import SwiftUI

/// Unified urgent list: mixes urgent tasks + today's upcoming calendar events,
/// sorted by urgency then time.
struct HotlistWidget: View {
    let tasks: [AppTask]
    let events: [CalendarEvent]
    let onToggle: (AppTask) -> Void

    @Environment(\.theme) private var theme

    private var items: [HotlistItem] {
        let now = Date()

        // Urgent tasks
        let taskItems = tasks
            .filter { $0.isUrgent && $0.section == .today }
            .map { HotlistItem.task($0) }

        // Today's upcoming non-all-day events
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        guard let tomorrow = cal.date(byAdding: .day, value: 1, to: today) else {
            return taskItems
        }
        let eventItems = events
            .filter { !$0.isAllDay && $0.startTime >= today && $0.startTime < tomorrow }
            .map { HotlistItem.event($0) }

        // Sort: urgent tasks first, then events by time
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
                        .font(.system(size: theme.fontSize, design: .monospaced))
                        .foregroundColor(ThemeManager.textSecondary)
                        .opacity(0.5)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Spacer()
                }
                .frame(maxHeight: .infinity)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(allItems) { item in
                        HotlistRow(item: item, onToggle: onToggle)
                    }
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
    }
}

// MARK: - Item Type

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
        case .task: return 0  // urgent tasks first
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

// MARK: - Row

struct HotlistRow: View {
    let item: HotlistItem
    let onToggle: (AppTask) -> Void
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: 8) {
            // Urgency dot
            urgencyDot

            // Text
            switch item {
            case .task(let task):
                Text(task.displayText)
                    .font(.system(size: theme.fontSize, design: .monospaced))
                    .foregroundColor(task.isDone ? ThemeManager.textSecondary : ThemeManager.textPrimary)
                    .strikethrough(task.isDone)
                    .opacity(task.isDone ? 0.28 : 1)
                    .lineLimit(1)
                    .onTapGesture { onToggle(task) }

            case .event(let event):
                Text(event.title)
                    .font(.system(size: theme.fontSize, design: .monospaced))
                    .foregroundColor(ThemeManager.textPrimary)
                    .lineLimit(1)
                    .opacity(event.isPast ? 0.38 : 1)
            }

            Spacer()

            // Due / time
            switch item {
            case .task:
                Text("Today")
                    .font(.system(size: theme.fontSize - 2, design: .monospaced))
                    .foregroundColor(ThemeManager.textSecondary)

            case .event(let event):
                Text(event.timeString)
                    .font(.system(size: theme.fontSize - 2, design: .monospaced))
                    .foregroundColor(ThemeManager.textSecondary)
            }
        }
    }

    @ViewBuilder
    private var urgencyDot: some View {
        switch item {
        case .task(let task):
            Circle()
                .fill(theme.accentFull)
                .frame(width: 8, height: 8)
                .shadow(color: task.isDone ? .clear : theme.accentFull.opacity(0.5), radius: 3)

        case .event:
            Circle()
                .strokeBorder(theme.accentFull, lineWidth: 1.5)
                .frame(width: 8, height: 8)
                .opacity(0.6)
        }
    }
}
