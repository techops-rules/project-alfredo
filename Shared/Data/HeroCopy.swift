import Foundation

/// Rotating dashboard headlines in the Monday-voice: simple, direct, mildly roasty.
/// Ported from the design prototype (`design/alfredo-hud/data.jsx` HEADLINES).
enum HeroCopy {
    static let headlines: [String] = [
        "three things matter today. the rest is noise.",
        "less thinking, more doing.",
        "one thing at a time. one.",
        "show up, make a dent, go home.",
        "the list doesn't shrink by staring at it.",
        "two hours of real work beats a full day of busy.",
        "fewer tabs. start there.",
        "inbox zero is a myth. next action isn't.",
        "the meeting doesn't prep itself.",
        "pick the hard one first. you'll coast after.",
        "call it done at 80%. ship.",
        "no one is grading the difficulty.",
        "future-you will thank current-you. eventually.",
        "you've got this. probably.",
        "the day started. you can keep up.",
        "progress, not performance."
    ]

    /// Deadpan, specific micro-facts that rotate alongside the headline.
    static let microFacts: [String] = [
        "you slept 5h 12m. brace.",
        "2,400 steps. legs are drafting a resignation letter.",
        "3 tasks shipped yesterday. respectable.",
        "coffee #2 was at 10:14. we're tracking.",
        "inbox: 6 live threads. four can wait.",
        "last water log was 11:47. it's 14:02.",
        "screen time: 4h 30m before noon. a choice.",
        "EUROTRIP · 14 days out. pack list is empty."
    ]

    // MARK: - Holidays

    /// Returns a short holiday label for the given date, or nil if none.
    /// Covers US federal holidays plus a handful of popular observances.
    /// Floating dates (MLK Day, Thanksgiving, Easter, Good Friday) are computed.
    static func holiday(for date: Date = Date()) -> String? {
        let cal = Calendar(identifier: .gregorian)
        let y = cal.component(.year, from: date)
        let m = cal.component(.month, from: date)
        let d = cal.component(.day, from: date)

        let fixed: [(Int, Int, String)] = [
            (1, 1, "New Year's Day"), (2, 2, "Groundhog Day"), (2, 14, "Valentine's Day"),
            (3, 17, "St. Patrick's Day"), (4, 1, "April Fool's"), (4, 22, "Earth Day"),
            (5, 5, "Cinco de Mayo"), (6, 14, "Flag Day"), (6, 19, "Juneteenth"),
            (7, 4, "Independence Day"), (10, 31, "Halloween"), (11, 11, "Veterans Day"),
            (12, 24, "Christmas Eve"), (12, 25, "Christmas"), (12, 31, "New Year's Eve")
        ]
        if let hit = fixed.first(where: { $0.0 == m && $0.1 == d }) { return hit.2 }

        // Floating (nth weekday of month)
        if m == 1, d == nthWeekday(3, weekday: 2, month: 1, year: y) { return "MLK Day" }
        if m == 2, d == nthWeekday(3, weekday: 2, month: 2, year: y) { return "Presidents' Day" }
        if m == 5, d == nthWeekday(2, weekday: 1, month: 5, year: y) { return "Mother's Day" }
        if m == 5, d == lastWeekday(2, month: 5, year: y) { return "Memorial Day" }
        if m == 6, d == nthWeekday(3, weekday: 1, month: 6, year: y) { return "Father's Day" }
        if m == 9, d == nthWeekday(1, weekday: 2, month: 9, year: y) { return "Labor Day" }
        if m == 10, d == nthWeekday(2, weekday: 2, month: 10, year: y) { return "Indigenous Peoples' Day" }
        if m == 11, d == nthWeekday(4, weekday: 5, month: 11, year: y) { return "Thanksgiving" }

        // Easter + Good Friday (Gauss algorithm; weekday values use 1=Sun)
        let easter = gaussEaster(year: y)
        if m == easter.month, d == easter.day { return "Easter" }
        if let gf = cal.date(byAdding: .day, value: -2, to: dateFrom(year: y, month: easter.month, day: easter.day)) {
            let gm = cal.component(.month, from: gf)
            let gd = cal.component(.day, from: gf)
            if m == gm, d == gd { return "Good Friday" }
        }
        return nil
    }

    // MARK: - Helpers

    /// Swift weekday: 1=Sun, 2=Mon, ..., 7=Sat
    private static func nthWeekday(_ n: Int, weekday: Int, month: Int, year: Int) -> Int {
        let cal = Calendar(identifier: .gregorian)
        var comps = DateComponents(); comps.year = year; comps.month = month; comps.day = 1
        guard let first = cal.date(from: comps) else { return 1 }
        let firstWd = cal.component(.weekday, from: first)
        let offset = (weekday - firstWd + 7) % 7
        return 1 + offset + (n - 1) * 7
    }

    private static func lastWeekday(_ weekday: Int, month: Int, year: Int) -> Int {
        let cal = Calendar(identifier: .gregorian)
        var comps = DateComponents(); comps.year = year; comps.month = month + 1; comps.day = 0
        guard let last = cal.date(from: comps) else { return 28 }
        let lastDay = cal.component(.day, from: last)
        let lastWd = cal.component(.weekday, from: last)
        let offset = (lastWd - weekday + 7) % 7
        return lastDay - offset
    }

    private static func dateFrom(year: Int, month: Int, day: Int) -> Date {
        let cal = Calendar(identifier: .gregorian)
        var c = DateComponents(); c.year = year; c.month = month; c.day = day
        return cal.date(from: c) ?? Date()
    }

    private static func gaussEaster(year y: Int) -> (month: Int, day: Int) {
        let a = y % 19
        let b = y / 100
        let c = y % 100
        let d = b / 4
        let e = b % 4
        let f = (b + 8) / 25
        let g = (b - f + 1) / 3
        let h = (19 * a + b - d - g + 15) % 30
        let i = c / 4
        let k = c % 4
        let L = (32 + 2 * e + 2 * i - h - k) % 7
        let m = (a + 11 * h + 22 * L) / 451
        let month = (h + L - 7 * m + 114) / 31
        let day = ((h + L - 7 * m + 114) % 31) + 1
        return (month, day)
    }

    // MARK: - Weather description + quip

    /// Brief one-line description of the day's weather plus an optional deadpan quip.
    /// Matches the prototype's `describeDay()` logic in `widgets.jsx`.
    static func describeDay(code: Int, cloudCover: Int, windMph: Double, hiF: Int,
                            hourlyTodayCodes: [Int]) -> (line: String, quip: String?) {
        let rainCodes: Set<Int> = [51,53,55,61,63,65,80,81,82,95,96,99]
        let snowCodes: Set<Int> = [71,73,75]
        let hour = Calendar.current.component(.hour, from: Date())
        let amCodes = Array(hourlyTodayCodes.prefix(min(12, hourlyTodayCodes.count)))
        let pmCodes = Array(hourlyTodayCodes.dropFirst(12).prefix(max(0, hourlyTodayCodes.count - 12)))
        let rainAm = amCodes.contains(where: rainCodes.contains)
        let rainPm = pmCodes.contains(where: rainCodes.contains)
        let snowAny = hourlyTodayCodes.contains(where: snowCodes.contains) || snowCodes.contains(code)

        var line: String
        if snowAny { line = "snow" }
        else if rainAm && rainPm { line = "rain all day" }
        else if rainAm && !rainPm { line = "rain am, clears" }
        else if !rainAm && rainPm { line = "rain later" }
        else if cloudCover >= 80 || code == 3 { line = "overcast" }
        else if cloudCover >= 40 { line = "partly cloudy" }
        else if hiF >= 85 { line = "sunny & hot" }
        else if hiF <= 40 { line = "sunny & cold" }
        else { line = "clear" }
        if windMph >= 18, !snowAny, line != "rain all day" { line += ", windy" }

        let base = line.components(separatedBy: ",").first?.trimmingCharacters(in: .whitespaces) ?? line
        let quips: [String: String] = [
            "snow": "(stay in)",
            "rain all day": "(sad song day)",
            "rain am, clears": "(wet shoes)",
            "rain later": "(bring a jacket)",
            "overcast": "(soup weather)",
            "sunny & hot": "(hydrate)",
            "sunny & cold": "(deceptive)"
        ]
        _ = hour  // reserved for future time-of-day-aware quips
        return (line, quips[base])
    }
}
