import Foundation

enum AttendanceStatus: String, Codable {
    case accepted
    case declined
    case tentative
    case pending // not yet responded
    case none    // no attendee info (you're the organizer, or solo event)
}

struct CalendarEvent: Identifiable, Codable {
    let id: String
    var title: String
    var startTime: Date
    var endTime: Date
    var location: String?
    var isAllDay: Bool
    var attendance: AttendanceStatus = .none

    var durationMinutes: Int {
        Int(endTime.timeIntervalSince(startTime) / 60)
    }

    var timeString: String {
        if isAllDay { return "All day" }
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f.string(from: startTime)
    }

    var relativeTimeString: String {
        let mins = Int(startTime.timeIntervalSinceNow / 60)
        if mins < 0 { return "now" }
        if mins < 60 { return "in \(mins) min" }
        let hrs = mins / 60
        return "in \(hrs) hr"
    }

    // Phase 1: static sample events
    static var sampleEvents: [CalendarEvent] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())

        return [
            CalendarEvent(
                id: "1",
                title: "Team Standup",
                startTime: cal.date(bySettingHour: 9, minute: 0, second: 0, of: today)!,
                endTime: cal.date(bySettingHour: 9, minute: 30, second: 0, of: today)!,
                location: "Google Meet",
                isAllDay: false
            ),
            CalendarEvent(
                id: "2",
                title: "1:1 with Manager",
                startTime: cal.date(bySettingHour: 11, minute: 0, second: 0, of: today)!,
                endTime: cal.date(bySettingHour: 11, minute: 30, second: 0, of: today)!,
                location: nil,
                isAllDay: false
            ),
            CalendarEvent(
                id: "3",
                title: "Lunch Break",
                startTime: cal.date(bySettingHour: 12, minute: 0, second: 0, of: today)!,
                endTime: cal.date(bySettingHour: 13, minute: 0, second: 0, of: today)!,
                location: nil,
                isAllDay: false
            ),
            CalendarEvent(
                id: "4",
                title: "Sprint Planning",
                startTime: cal.date(bySettingHour: 14, minute: 0, second: 0, of: today)!,
                endTime: cal.date(bySettingHour: 15, minute: 0, second: 0, of: today)!,
                location: "Zoom",
                isAllDay: false
            ),
            CalendarEvent(
                id: "5",
                title: "Focus Block",
                startTime: cal.date(bySettingHour: 15, minute: 30, second: 0, of: today)!,
                endTime: cal.date(bySettingHour: 17, minute: 0, second: 0, of: today)!,
                location: nil,
                isAllDay: false
            ),
        ]
    }
}
