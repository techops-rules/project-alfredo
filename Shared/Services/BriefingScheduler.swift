import Foundation
import UserNotifications

/// Schedules morning briefing compilation and pre-meeting reminders.
/// Runs as a singleton, started on app launch.
@Observable
final class BriefingScheduler {
    static let shared = BriefingScheduler()

    private var checkTimer: Timer?
    private var notifiedEventIds: Set<String> = []
    private var morningBriefSentToday: Date?

    /// Minutes before meeting to send reminder
    private let preMeetingMinutes: Int = 25

    /// Hour to send morning briefing (24h)
    private let morningBriefHour: Int = 8

    private init() {}

    /// Start the scheduler -- call from app launch
    func start() {
        requestNotificationPermission()

        // Check every 60 seconds
        checkTimer?.invalidate()
        checkTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.tick()
        }
        // Note: don't run immediately on app launch — let CalendarService initialize first
        // tick()
    }

    func stop() {
        checkTimer?.invalidate()
        checkTimer = nil
    }

    // MARK: - Tick

    private func tick() {
        let now = Date()
        let cal = Calendar.current

        // Morning briefing: around 8am, once per day
        checkMorningBrief(now: now, cal: cal)

        // Pre-meeting reminders: 25 min before each event
        checkPreMeetingReminders(now: now, cal: cal)
    }

    // MARK: - Morning Brief

    private func checkMorningBrief(now: Date, cal: Calendar) {
        let hour = cal.component(.hour, from: now)

        // Already sent today?
        if let sent = morningBriefSentToday, cal.isDate(sent, inSameDayAs: now) {
            return
        }

        // Send between 8:00 and 8:15
        guard hour == morningBriefHour, cal.component(.minute, from: now) < 15 else { return }

        let events = CalendarService.shared.events
        let todaysEvents = events.filter { event in
            cal.isDate(event.startTime, inSameDayAs: now)
            && event.attendance != .declined
            && !event.isAllDay
        }

        guard !todaysEvents.isEmpty else { return }

        morningBriefSentToday = now

        // Pre-load all briefings
        MeetingPrepService.shared.preloadTodaysBriefings(events: todaysEvents)

        // Build morning briefing summary
        let summary = buildMorningSummary(events: todaysEvents)
        sendNotification(
            title: "ALFREDO DAILY BRIEF",
            body: summary,
            id: "morning-brief-\(cal.component(.day, from: now))-\(cal.component(.month, from: now))"
        )
    }

    private func buildMorningSummary(events: [CalendarEvent]) -> String {
        let count = events.count
        var lines: [String] = ["\(count) meeting\(count == 1 ? "" : "s") today"]

        // Check for back-to-back
        let sorted = events.sorted { $0.startTime < $1.startTime }
        var backToBackPairs = 0
        for i in 0..<sorted.count - 1 {
            let gap = sorted[i + 1].startTime.timeIntervalSince(sorted[i].endTime)
            if gap < 10 * 60 { // less than 10 min gap
                backToBackPairs += 1
            }
        }
        if backToBackPairs > 0 {
            lines.append("\(backToBackPairs) back-to-back -- want bundled briefs?")
        }

        // First meeting
        if let first = sorted.first {
            lines.append("First: \(first.title) at \(first.timeString)")
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - Pre-Meeting Reminders

    private func checkPreMeetingReminders(now: Date, cal: Calendar) {
        let events = CalendarService.shared.events
        let todaysEvents = events.filter { event in
            cal.isDate(event.startTime, inSameDayAs: now)
            && event.attendance != .declined
            && !event.isAllDay
            && !event.isPast
        }

        for event in todaysEvents {
            let minutesUntil = Int(event.startTime.timeIntervalSince(now) / 60)

            // Send notification at ~25 min mark (window: 24-26 min)
            guard minutesUntil >= preMeetingMinutes - 1,
                  minutesUntil <= preMeetingMinutes + 1,
                  !notifiedEventIds.contains(event.id) else { continue }

            notifiedEventIds.insert(event.id)

            sendNotification(
                title: "\(event.title) in \(minutesUntil) min",
                body: "Tap to read your meeting brief",
                id: "pre-meeting-\(event.id)"
            )
        }

        // Clean up old notification IDs (events from yesterday)
        notifiedEventIds = notifiedEventIds.filter { id in
            events.contains { $0.id == id && !$0.isPast }
        }
    }

    // MARK: - Notifications

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    private func sendNotification(title: String, body: String, id: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: id,
            content: content,
            trigger: nil // deliver immediately
        )

        UNUserNotificationCenter.current().add(request)
    }
}
