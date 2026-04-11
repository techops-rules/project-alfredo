import SwiftUI
struct CalendarWidget: View {
    let events: [CalendarEvent]
    @Environment(\.theme) private var theme
    
    private var todaysEvents: [CalendarEvent] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let tomorrow = cal.date(byAdding: .day, value: 1, to: today)!
        
        return events.filter { event in
            event.startTime >= today && event.startTime < tomorrow
        }
    }
    
    private var todayString: String {
        let f = DateFormatter()
        f.dateFormat = "EEE, MMM d"
        return f.string(from: Date()).uppercased()
    }
    
    var body: some View {
        WidgetShell(
            title: "CALENDAR.DAT",
            badge: "\(todaysEvents.count) today",
            zone: "primary"
        ) {
            VStack(spacing: 12) {
                // Today indicator
                HStack(spacing: 8) {
                    Text(todayString)
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundColor(theme.accentFull)
                    Spacer()
                    Text("\(todaysEvents.count) event\(todaysEvents.count == 1 ? "" : "s")")
                        .font(.system(size: 9, weight: .regular, design: .monospaced))
                        .foregroundColor(ThemeManager.textSecondary)
                }
                
                Divider().background(ThemeManager.textSecondary.opacity(0.2))
                
                // Event list — today only
                if todaysEvents.isEmpty {
                    Text("no events today")
                        .font(.system(size: theme.fontSize, design: .monospaced))
                        .foregroundColor(ThemeManager.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 8)
                } else {
                    VStack(spacing: 8) {
                        ForEach(todaysEvents) { event in
                            let dimmed = event.attendance == .pending || event.attendance == .declined || event.attendance == .tentative
                            HStack(spacing: 10) {
                                Text(event.timeString)
                                    .font(.system(size: theme.fontSize - 1, weight: .medium, design: .monospaced))
                                    .foregroundColor(dimmed ? ThemeManager.textSecondary.opacity(0.4) : theme.accentFull)
                                    .frame(width: 70, alignment: .leading)
                                Text(event.title)
                                    .font(.system(size: theme.fontSize, design: .monospaced))
                                    .foregroundColor(dimmed ? ThemeManager.textSecondary.opacity(0.5) : ThemeManager.textPrimary)
                                    .lineLimit(1)
                                Spacer()
                                if dimmed {
                                    Text(event.attendance == .declined ? "declined" : "pending")
                                        .font(.system(size: theme.fontSize - 2, design: .monospaced))
                                        .foregroundColor(ThemeManager.textSecondary.opacity(0.35))
                                } else {
                                    Text("\(event.durationMinutes) min")
                                        .font(.system(size: theme.fontSize - 2, design: .monospaced))
                                        .foregroundColor(ThemeManager.textSecondary)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
