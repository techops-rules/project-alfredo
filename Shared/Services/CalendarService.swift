import Foundation
import EventKit

@Observable
final class CalendarService {
    static let shared = CalendarService()

    private let eventStore = EKEventStore()
    @ObservationIgnored private var calendars: [EKCalendar] = []
    @ObservationIgnored private var refreshTimer: Timer?

    var events: [CalendarEvent] = []
    var isAuthorized = false

    private init() {
        requestAccess()

        // Refresh every 5 minutes
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            self?.loadEvents()
        }

        // Refresh when calendar store changes (events added/deleted externally)
        NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged, object: eventStore, queue: .main
        ) { [weak self] _ in
            self?.loadEvents()
        }
    }

    // Request calendar access — only prompts if not yet determined
    private func requestAccess() {
        let status = EKEventStore.authorizationStatus(for: .event)

        // Already have access — just load
        if status == .fullAccess || status == .authorized {
            isAuthorized = true
            loadEvents()
            return
        }

        // Denied or restricted — don't prompt
        if status == .denied || status == .restricted {
            isAuthorized = false
            return
        }

        // writeOnly (macOS 14+) — treat as needing upgrade, but don't prompt every time
        if #available(macOS 14.0, iOS 17.0, *) {
            if status == .writeOnly {
                // We have write but not read — need to request full access once
                let hasAsked = UserDefaults.standard.bool(forKey: "calendar.fullAccessAsked")
                if hasAsked {
                    isAuthorized = false
                    return
                }
                UserDefaults.standard.set(true, forKey: "calendar.fullAccessAsked")
            }
        }

        // Only reach here for .notDetermined (or first writeOnly upgrade)
        if status != .notDetermined {
            // Unknown status — don't prompt
            isAuthorized = false
            return
        }

        if #available(macOS 14.0, iOS 17.0, *) {
            eventStore.requestFullAccessToEvents { [weak self] granted, error in
                DispatchQueue.main.async {
                    self?.isAuthorized = granted
                    if granted { self?.loadEvents() }
                }
            }
        } else {
            eventStore.requestAccess(to: .event) { [weak self] granted, error in
                DispatchQueue.main.async {
                    self?.isAuthorized = granted
                    if granted { self?.loadEvents() }
                }
            }
        }
    }

    // Load events from system calendar
    func loadEvents() {
        guard isAuthorized else { return }

        let today = Calendar.current.startOfDay(for: Date())
        let oneWeekLater = Calendar.current.date(byAdding: .day, value: 7, to: today)!
        let predicate = eventStore.predicateForEvents(withStart: today, end: oneWeekLater, calendars: nil)

        let ekEvents = eventStore.events(matching: predicate)

        let mapped: [CalendarEvent] = ekEvents.map { ekEvent in
            CalendarEvent(
                id: ekEvent.eventIdentifier,
                title: ekEvent.title ?? "",
                startTime: ekEvent.startDate,
                endTime: ekEvent.endDate ?? ekEvent.startDate,
                location: ekEvent.location,
                isAllDay: ekEvent.isAllDay,
                attendance: attendanceStatus(for: ekEvent)
            )
        }
        events = mapped.sorted { $0.startTime < $1.startTime }
    }

    // Refresh events
    func refresh() {
        loadEvents()
    }

    private func attendanceStatus(for event: EKEvent) -> AttendanceStatus {
        // If no attendees, it's a solo event
        guard let attendees = event.attendees, !attendees.isEmpty else { return .none }
        // Find the current user's participant status
        if let me = attendees.first(where: { $0.isCurrentUser }) {
            switch me.participantStatus {
            case .accepted:   return .accepted
            case .declined:   return .declined
            case .tentative:  return .tentative
            case .pending:    return .pending
            default:          return .pending
            }
        }
        // Organizer with no attendee entry for self
        return .none
    }

    // Create a new event in system calendar
    func createEvent(title: String, startDate: Date, endDate: Date, notes: String = "") -> Bool {
        guard isAuthorized else { return false }

        let event = EKEvent(eventStore: eventStore)
        event.title = title
        event.startDate = startDate
        event.endDate = endDate
        event.notes = notes

        if let defaultCalendar = eventStore.defaultCalendarForNewEvents {
            event.calendar = defaultCalendar
            do {
                try eventStore.save(event, span: .thisEvent)
                loadEvents()
                return true
            } catch {
                print("Failed to create event: \(error)")
                return false
            }
        }
        return false
    }
}
