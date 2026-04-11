import SwiftUI

struct CalendarWidget: View {
    let events: [CalendarEvent]
    var weekendMode: Bool = false
    @Environment(\.theme) private var theme
    @State private var selectedEvent: CalendarEvent?

    /// Active + upcoming events for today
    private func activeEvents(at now: Date) -> [CalendarEvent] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        guard let tomorrow = cal.date(byAdding: .day, value: 1, to: today) else { return [] }
        return events.filter { $0.startTime >= today && $0.startTime < tomorrow && $0.endTime > now }
    }

    /// Weekend events (Sat+Sun of the coming weekend), T&S calendar first
    private func weekendEvents(at now: Date) -> [CalendarEvent] {
        let cal = Calendar.current
        let weekday = cal.component(.weekday, from: now) // 1=Sun,2=Mon,...,6=Fri,7=Sat

        let daysUntilSat: Int
        switch weekday {
        case 7: daysUntilSat = 0   // Saturday already
        case 1: daysUntilSat = 6   // Sunday — show next weekend
        case 6: daysUntilSat = 1   // Friday night — tomorrow
        default: daysUntilSat = 7 - weekday + 1
        }

        guard let saturday = cal.date(byAdding: .day, value: daysUntilSat, to: cal.startOfDay(for: now)),
              let monday   = cal.date(byAdding: .day, value: 2, to: saturday) else { return [] }

        return events
            .filter { !$0.isAllDay && $0.startTime >= saturday && $0.startTime < monday }
            .sorted { a, b in
                let aIsTS = isTS(a)
                let bIsTS = isTS(b)
                if aIsTS != bIsTS { return aIsTS }
                return a.startTime < b.startTime
            }
    }

    private func isTS(_ event: CalendarEvent) -> Bool {
        guard let name = event.calendarName?.lowercased() else { return false }
        return name.contains("t&s") || name.contains("t & s") || name.contains("sierra")
    }

    private func headerString(at now: Date) -> String {
        if weekendMode {
            let cal = Calendar.current
            let weekday = cal.component(.weekday, from: now)
            let daysUntilSat = weekday == 7 ? 0 : weekday == 1 ? 6 : weekday == 6 ? 1 : 7 - weekday + 1
            guard let sat = cal.date(byAdding: .day, value: daysUntilSat, to: cal.startOfDay(for: now)),
                  let sun = cal.date(byAdding: .day, value: 1, to: sat) else {
                return "WEEKEND"
            }
            let f = DateFormatter(); f.dateFormat = "MMM d"
            return "WKD \(f.string(from: sat).uppercased()) – \(f.string(from: sun).uppercased())"
        }
        let f = DateFormatter(); f.dateFormat = "EEE, MMM d"
        return f.string(from: now).uppercased()
    }

    var body: some View {
        // TimelineView refreshes every 60s so events auto-clear and live states update
        TimelineView(.periodic(from: .now, by: 60)) { timeline in
            let now = timeline.date
            let visible = weekendMode ? weekendEvents(at: now) : activeEvents(at: now)
            let emptyMsg = weekendMode ? "no weekend events" : "no more events today"

            WidgetShell(
                title: "CALENDAR.DAT",
                badge: weekendMode ? "WKD" : "\(visible.count) today",
                zone: "primary"
            ) {
                VStack(spacing: 12) {
                    // Date header
                    HStack(spacing: 8) {
                        Text(headerString(at: now))
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundColor(theme.accentFull)
                        Spacer()
                        Text("\(visible.count) event\(visible.count == 1 ? "" : "s")")
                            .font(.system(size: 9, weight: .regular, design: .monospaced))
                            .foregroundColor(ThemeManager.textSecondary)
                    }

                    Divider().background(ThemeManager.textSecondary.opacity(0.2))

                    // Event list
                    if visible.isEmpty {
                        Text(emptyMsg)
                            .font(.system(size: theme.fontSize, design: .monospaced))
                            .foregroundColor(ThemeManager.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 8)
                    } else {
                        VStack(spacing: 8) {
                            ForEach(visible) { event in
                                CalendarEventRow(event: event, now: now, showDay: weekendMode)
                                    .contentShape(Rectangle())
                                    .onLongPressGesture(minimumDuration: 0.5) {
                                        selectedEvent = event
                                    }
                            }
                        }
                    }
                }
            }
        }
        .sheet(item: $selectedEvent) { event in
            EventBriefingSheet(event: event)
                #if os(iOS)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                #endif
        }
    }
}

// MARK: - Event Row

struct CalendarEventRow: View {
    let event: CalendarEvent
    let now: Date
    var showDay: Bool = false
    @Environment(\.theme) private var theme
    @State private var displayState: MeetingDisplayState = .collapsed

    enum MeetingDisplayState: CaseIterable {
        case collapsed, brief, full
        var next: MeetingDisplayState {
            let all = Self.allCases
            guard let idx = all.firstIndex(of: self) else { return .collapsed }
            return all[(idx + 1) % all.count]
        }
    }

    private var dimmed: Bool {
        event.attendance == .pending || event.attendance == .declined || event.attendance == .tentative
    }

    private var isPast: Bool {
        event.endTime <= now
    }

    private var briefText: String {
        let end = event.endTime
        let fmt = DateFormatter()
        fmt.dateFormat = "h:mm a"
        let range = event.timeString + " – " + fmt.string(from: end)
        return range + " · " + "\(event.durationMinutes) min"
    }

    private var fullText: String {
        var lines: [String] = []
        if let loc = event.location, !loc.isEmpty {
            lines.append("📍 " + loc)
        }
        if let names = event.attendeeNames, !names.isEmpty {
            lines.append("👥 " + names.joined(separator: ", "))
        }
        if lines.isEmpty {
            lines.append("No additional context available")
        }
        return lines.joined(separator: "\n")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                // Live indicator bar
                if event.isLive {
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(theme.accentFull)
                        .frame(width: 3, height: 20)
                        .shadow(color: theme.accentFull.opacity(0.5), radius: 4)
                } else if event.isStartingSoon {
                    PulsingBar(color: theme.accentFull)
                        .frame(width: 3, height: 20)
                }

                // Time
                VStack(alignment: .leading, spacing: 2) {
                    if showDay {
                        let f: DateFormatter = {
                            let df = DateFormatter(); df.dateFormat = "EEE h:mm a"; return df
                        }()
                        Text(f.string(from: event.startTime).uppercased())
                            .font(.system(size: theme.fontSize - 1, weight: .medium, design: .monospaced))
                            .foregroundColor(dimmed ? ThemeManager.textSecondary.opacity(0.4) : theme.accentFull)
                            .frame(width: 100, alignment: .leading)
                    } else {
                        Text(event.timeString)
                            .font(.system(size: theme.fontSize - 1, weight: event.isLive ? .bold : .medium, design: .monospaced))
                            .foregroundColor(dimmed ? ThemeManager.textSecondary.opacity(0.4) : theme.accentFull)
                            .frame(width: 70, alignment: .leading)

                        if event.isLive || event.isStartingSoon {
                            Text(event.isLive ? "NOW" : "in \(event.minutesUntilStart)m")
                                .font(.system(size: theme.fontSize - 3, weight: .bold, design: .monospaced))
                                .foregroundColor(event.isLive ? ThemeManager.success : ThemeManager.warning)
                        }
                    }
                }

                // Title
                Text(event.title)
                    .font(.system(size: theme.fontSize, weight: event.isLive ? .bold : .regular, design: .monospaced))
                    .foregroundColor(dimmed ? ThemeManager.textSecondary.opacity(0.5) : ThemeManager.textPrimary)
                    .lineLimit(1)

                Spacer()

                // Hint / status
                if displayState == .collapsed {
                    Text("tap for brief")
                        .font(.system(size: theme.fontSize - 4, design: .monospaced))
                        .foregroundColor(ThemeManager.textSecondary.opacity(0.4))
                } else if dimmed {
                    Text(event.attendance == .declined ? "declined" : "pending")
                        .font(.system(size: theme.fontSize - 2, design: .monospaced))
                        .foregroundColor(ThemeManager.textSecondary.opacity(0.35))
                } else {
                    Text("\(event.durationMinutes) min")
                        .font(.system(size: theme.fontSize - 2, design: .monospaced))
                        .foregroundColor(ThemeManager.textSecondary)
                }
            }

            // Brief detail
            if displayState == .brief || displayState == .full {
                Text(briefText)
                    .font(.system(size: theme.fontSize - 2, design: .monospaced))
                    .foregroundColor(ThemeManager.textPrimary)
                    .padding(.leading, 16)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            // Full context
            if displayState == .full {
                Text(fullText)
                    .font(.system(size: theme.fontSize - 2, design: .monospaced))
                    .foregroundColor(ThemeManager.textSecondary)
                    .lineSpacing(4)
                    .padding(.leading, 16)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .opacity(isPast ? 0.38 : 1.0)
        .onTapGesture {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                displayState = displayState.next
            }
        }
    }
}

// MARK: - Pulsing Bar (pre-meeting warning)

struct PulsingBar: View {
    let color: Color
    @State private var isPulsing = false

    var body: some View {
        RoundedRectangle(cornerRadius: 1.5)
            .fill(color)
            .opacity(isPulsing ? 1.0 : 0.4)
            .shadow(color: color.opacity(isPulsing ? 0.6 : 0.1), radius: isPulsing ? 6 : 2)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                    isPulsing = true
                }
            }
    }
}
