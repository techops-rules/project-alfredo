import SwiftUI

struct CalendarWidget: View {
    let events: [CalendarEvent]
    @Environment(\.theme) private var theme
    @State private var selectedEvent: CalendarEvent?

    /// Active + upcoming events only (past events auto-clear)
    private func activeEvents(at now: Date) -> [CalendarEvent] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        guard let tomorrow = cal.date(byAdding: .day, value: 1, to: today) else { return [] }

        return events.filter { event in
            event.startTime >= today && event.startTime < tomorrow && event.endTime > now
        }
    }

    private var todayString: String {
        let f = DateFormatter()
        f.dateFormat = "EEE, MMM d"
        return f.string(from: Date()).uppercased()
    }

    var body: some View {
        // TimelineView refreshes every 60s so events auto-clear and live states update
        TimelineView(.periodic(from: .now, by: 60)) { timeline in
            let now = timeline.date
            let visible = activeEvents(at: now)

            WidgetShell(
                title: "CALENDAR.DAT",
                badge: "\(visible.count) today",
                zone: "primary"
            ) {
                VStack(spacing: 12) {
                    // Today indicator
                    HStack(spacing: 8) {
                        Text(todayString)
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
                        Text("no more events today")
                            .font(.system(size: theme.fontSize, design: .monospaced))
                            .foregroundColor(ThemeManager.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 8)
                    } else {
                        VStack(spacing: 8) {
                            ForEach(visible) { event in
                                CalendarEventRow(event: event, now: now)
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
    @Environment(\.theme) private var theme
    @State private var displayState: MeetingDisplayState = .collapsed

    enum MeetingDisplayState: CaseIterable {
        case collapsed, brief, full
        var next: MeetingDisplayState {
            let all = Self.allCases
            let idx = all.firstIndex(of: self)!
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
