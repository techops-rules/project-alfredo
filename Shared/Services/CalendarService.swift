import Foundation
import EventKit

@Observable
final class CalendarService {
    static let shared = CalendarService()

    private let eventStore = EKEventStore()
    @ObservationIgnored private var calendars: [EKCalendar] = []
    @ObservationIgnored private var refreshTimer: Timer?
    @ObservationIgnored private var storeObserver: Any?

    var events: [CalendarEvent] = []
    var isAuthorized = false

    private init() {
        requestAccess()

        // Refresh every 5 minutes
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            self?.loadEvents()
        }

        // Refresh when calendar store changes (events added/deleted externally)
        storeObserver = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged, object: eventStore, queue: .main
        ) { [weak self] _ in
            self?.loadEvents()
        }
    }

    deinit {
        refreshTimer?.invalidate()
        if let observer = storeObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    // Request calendar access — only prompts if not yet determined
    private func requestAccess() {
        let status = EKEventStore.authorizationStatus(for: .event)

        // Already have access — just load.
        if status == .fullAccess || status == .authorized {
            isAuthorized = true
            loadEvents()
            return
        }

        // Denied or restricted — don't prompt.
        if status == .denied || status == .restricted {
            isAuthorized = false
            return
        }

        // writeOnly (macOS 14+/iOS 17+) means we can write but not read.
        // We should request full access upgrade once.
        if #available(macOS 14.0, iOS 17.0, *) {
            if status == .writeOnly {
                let hasAsked = UserDefaults.standard.bool(forKey: "calendar.fullAccessAsked")
                if hasAsked {
                    isAuthorized = false
                    return
                }
                UserDefaults.standard.set(true, forKey: "calendar.fullAccessAsked")
                eventStore.requestFullAccessToEvents { [weak self] granted, _ in
                    DispatchQueue.main.async {
                        self?.isAuthorized = granted
                        if granted { self?.loadEvents() }
                    }
                }
                return
            }
        }

        // Only prompt on first run.
        if status != .notDetermined {
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
        guard let oneWeekLater = Calendar.current.date(byAdding: .day, value: 7, to: today) else { return }
        let predicate = eventStore.predicateForEvents(withStart: today, end: oneWeekLater, calendars: nil)

        let ekEvents = eventStore.events(matching: predicate)

        let mapped: [CalendarEvent] = ekEvents.map { ekEvent in
            let attendees = ekEvent.attendees?.compactMap { $0.name ?? $0.url.absoluteString } ?? []
            let organizer = ekEvent.organizer?.name

            return CalendarEvent(
                id: ekEvent.eventIdentifier,
                title: ekEvent.title ?? "",
                startTime: ekEvent.startDate,
                endTime: ekEvent.endDate ?? ekEvent.startDate,
                location: ekEvent.location,
                isAllDay: ekEvent.isAllDay,
                attendance: attendanceStatus(for: ekEvent),
                notes: ekEvent.notes,
                url: ekEvent.url,
                organizerName: organizer,
                attendeeNames: attendees.isEmpty ? nil : attendees,
                isRecurring: ekEvent.hasRecurrenceRules,
                calendarName: ekEvent.calendar.title
            )
        }
        events = mapped.sorted { $0.startTime < $1.startTime }
        pushToPi()
    }

    // Push events to Pi kiosk for hybrid calendar display
    private func pushToPi() {
        let host = UserDefaults.standard.string(forKey: "terminal.piHost") ?? "pihub.local"
        let port = UserDefaults.standard.integer(forKey: "terminal.piPort")
        let kioskPort = port > 0 ? port + 10 : 8430  // bridge=8420, kiosk=8430
        guard let url = URL(string: "http://\(host):\(kioskPort)/proxy/calendar") else { return }

        let iso = ISO8601DateFormatter()
        let payload: [[String: Any]] = events.map { e in
            var d: [String: Any] = [
                "title": e.title,
                "startTime": iso.string(from: e.startTime),
                "endTime": iso.string(from: e.endTime),
                "isAllDay": e.isAllDay,
            ]
            if let loc = e.location { d["location"] = loc }
            if let org = e.organizerName { d["organizer"] = org }
            if let att = e.attendeeNames { d["attendees"] = att }
            if let notes = e.notes { d["notes"] = String(notes.prefix(200)) }
            if let cal = e.calendarName { d["calendar"] = cal }
            return d
        }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 5
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["events": payload])
        URLSession.shared.dataTask(with: req) { _, _, _ in }.resume()
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
