import Foundation

@Observable
final class iCloudService {
    static let shared = iCloudService()

    private(set) var baseURL: URL
    private(set) var isUsingiCloud: Bool = false

    private init() {
        if let icloudURL = FileManager.default.url(forUbiquityContainerIdentifier: "iCloud.com.projectalfredo.app") {
            self.baseURL = icloudURL.appendingPathComponent("Documents")
            self.isUsingiCloud = true
        } else {
            // Local fallback
            let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            self.baseURL = docs.appendingPathComponent("alfredo")
            self.isUsingiCloud = false
        }
        ensureStructure()
    }

    // MARK: - File Paths

    var taskBoardURL: URL { baseURL.appendingPathComponent("Task Board.md") }
    var scratchpadURL: URL { baseURL.appendingPathComponent("Scratchpad.md") }
    var memoryURL: URL { baseURL.appendingPathComponent(".claude/memory.md") }
    var habitsURL: URL { baseURL.appendingPathComponent("Habits.md") }
    var goalsURL: URL { baseURL.appendingPathComponent("Goals.md") }
    var layoutURL: URL { baseURL.appendingPathComponent(".config/layout.json") }
    var dailyNotesURL: URL { baseURL.appendingPathComponent("Daily Notes") }
    var meetingsURL: URL { baseURL.appendingPathComponent("Meetings") }
    var templatesURL: URL { baseURL.appendingPathComponent("Templates") }

    // MARK: - Read / Write

    func readFile(at url: URL) -> String? {
        try? String(contentsOf: url, encoding: .utf8)
    }

    func writeFile(at url: URL, content: String) {
        let dir = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? content.write(to: url, atomically: true, encoding: .utf8)
    }

    func readFileData(at url: URL) -> Data? {
        try? Data(contentsOf: url)
    }

    func writeFileData(_ data: Data, to url: URL) {
        let dir = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }

    // MARK: - Structure Setup

    private func ensureStructure() {
        let fm = FileManager.default
        let dirs = [baseURL, dailyNotesURL, meetingsURL, templatesURL, baseURL.appendingPathComponent(".claude")]
        for dir in dirs {
            if !fm.fileExists(atPath: dir.path) {
                try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
            }
        }

        seedIfNeeded(taskBoardURL, content: Self.defaultTaskBoard)
        seedIfNeeded(scratchpadURL, content: Self.defaultScratchpad)
        seedIfNeeded(memoryURL, content: Self.defaultMemory)
        seedIfNeeded(habitsURL, content: Self.defaultHabits)
        seedIfNeeded(goalsURL, content: Self.defaultGoals)
    }

    private func seedIfNeeded(_ url: URL, content: String) {
        if !FileManager.default.fileExists(atPath: url.path) {
            writeFile(at: url, content: content)
        }
    }

    // MARK: - Default Content

    static let defaultTaskBoard = """
    # Task Board

    ## Today
    - [ ]

    ## Soon
    -

    ## Later
    -

    ## Waiting
    -

    ## Agenda
    -

    ## Inbox
    -

    ## Done
    -

    ## Reference
    -

    ---

    **Task Format Notes:**
    - Today items: `- [ ] Task description [src:source] @scope`
    - Scope: `@work` or `@personal` (omit = assume work)
    - Source: `[src:email-MMDDYY-subject]` or `[src:cal-MMDDYY-event]` or `[src:manual]`

    **Rollover Behavior:**
    - Unchecked Today items automatically move to tomorrow's Today at /wrap-up
    - Checked items move to Done
    - Important tasks stay visible until completed
    """

    static let defaultScratchpad = """
    # Scratchpad

    Quick capture zone. Jot anything here throughout the day.
    Processed during /sync and /wrap-up, then cleared.

    ---

    """

    static let defaultMemory = """
    # Memory

    ## Now
    - Building Alfredo v0.426001

    ## Open Threads
    -

    ## Parked
    -

    ## People & Context
    -

    ## Recent Decisions
    -
    """

    static let defaultHabits = """
    # Habits

    - Morning workout
    - Read 30 min
    - Meditate
    - Journal
    - Exercise
    """

    static let defaultGoals = """
    # Goals

    - Ship Alfredo v1.0 | May 2026 | 10%
    - Read 20 books | Dec 2026 | 0%
    - Save $12k | Dec 2026 | 0%
    """
}
