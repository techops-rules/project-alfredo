# Implementation Plan: Calendar & Todo Intelligence Layer

**Goal:** Make calendar events and todos interactive, time-aware, and context-rich across all alfredo surfaces (iOS, macOS, Pi kiosk). Events auto-clear after they pass, live events get visual emphasis with a pre-meeting flash, and tapping any event or todo triggers a context briefing with confidence scores. Widget content should scale responsively to the container size the user sets.

---

## Pre-Work: Stability Audit (Claude Code should run this first)

Codebase scan turned up issues that should be fixed before building new features on top. Grouped by priority.

### CRITICAL (fix before feature work)

| # | File | Issue |
|---|------|-------|
| S1 | `pi-kiosk/serve.py:44-46` | **Command injection** -- `wlr-randr` command built via f-string from request body. Attacker can break out of the command. Fix: use subprocess args array directly, never interpolate user input into shell strings. |
| S2 | `pi-kiosk/index.html:313` | **Stored XSS** -- task text inserted via `innerHTML` without escaping. `settings.html` has an `esc()` function but `index.html` doesn't use it. Fix: use `textContent` or port the `esc()` helper. |
| S3 | `pi-kiosk/serve.py:32-48` | **Unauthenticated system control** -- `/exit-kiosk`, `/reload-kiosk`, `/proxy/display` have no auth. Any network client can kill chromium or blank the screen. Fix: restrict to localhost or add a bearer token check. |
| S4 | `CalendarWidget.swift:9` | **Force unwrap crash** -- `cal.date(byAdding: .day, value: 1, to: today)!` can return nil in edge timezone scenarios. Fix: guard let with fallback. |
| S5 | `CalendarService.swift:90` | **Force unwrap crash** -- same pattern, `date(byAdding: .day, value: 7, to: today)!`. Fix: guard let. |
| S6 | `iCloudService.swift:16` | **Force unwrap crash** -- `FileManager.default.urls(...).first!`. Fix: guard let with graceful fallback. |

### HIGH (fix during feature work)

| # | File | Issue |
|---|------|-------|
| S7 | `CalendarService.swift:24-28` | **Memory leak** -- NotificationCenter observer added in init, never removed. Singleton so low practical risk, but should add `deinit { NotificationCenter.default.removeObserver(...) }`. |
| S8 | `WebSocketSession.swift:79-86` | **Race condition** -- `receiveTask` and `pingTask` can be nil'd in `cleanup()` while `receiveLoop()` is running. Fix: add a lock or check task state before access. |
| S9 | `DashboardView.swift:5-7` | **@State vs @StateObject misuse** -- `TaskBoardService()` and `ScratchpadService()` created as `@State` instead of using the proper `@Observable` pattern. Can cause state loss on view redraws. |
| S10 | `pi-kiosk/serve.py:37-39,45-46` | **Subprocess hangs** -- `Popen()` without timeout. If chromium or bash hangs, the HTTP server thread blocks indefinitely. Fix: add timeout or use `communicate(timeout=...)`. |
| S11 | `pi-kiosk/serve.py:41-42` | **Memory exhaustion** -- no max Content-Length check before `rfile.read(length)`. Fix: cap at 1MB. |
| S12 | `pi-kiosk/serve.py:10,69,78,94` | **Bare except clauses** -- catches everything including SystemExit/KeyboardInterrupt. Fix: use `except Exception:`. |
| S13 | `alfredo-bridge.py:59,138` | **Hardcoded paths** -- `cwd="/home/todd"`. Fix: use `os.path.expanduser("~")`. |

### INFO (fix opportunistically)

| # | File | Issue |
|---|------|-------|
| S14 | `index.html:299-300` | localStorage quota not handled, silent data loss on `setItem()` |
| S15 | `index.html:510-527` | 2-second polling race between settings.html writes and index.html reads |
| S16 | `TerminalWidget.swift:432-477` | URLSession HTTP request not cancellable if view is dismissed |
| S17 | `WebSocketSession.swift:34-39` | UserDefaults access uses unsafe casting pattern, no type validation |
| S18 | `index.html:295,395,415` | fetch() calls with `.catch(()=>{})` silently swallow all errors |

### How Claude Code should handle this

Add a step at the start of the implementation session: "Run stability fixes (S1-S13) before starting Phase 0." The critical and high items are small, targeted changes. Each is a single file edit with a clear fix. Total effort: ~1.5 hours.

The INFO items (S14-S18) can be fixed as they're encountered during feature work.

---

## Phase 0: Responsive Widget Content (All Widgets, All Surfaces)

Widgets currently use fixed frames via `DraggableWidgetContainer` (min 200x100, snap-to-grid 20px, persisted via `WidgetLayoutManager`). The container size is user-controlled via drag-resize. But the content inside does NOT adapt -- font sizes, item counts, and layout are all hardcoded regardless of how big or small the user makes the widget.

### 0A. iOS/macOS -- GeometryReader-based content scaling

**Files to modify:**
- `Shared/Views/Components/WidgetShell.swift`
- `Shared/Views/Dashboard/CalendarWidget.swift`
- `Shared/Views/Dashboard/TaskListWidget.swift`
- `Shared/Views/Components/TodoItemView.swift`
- All other widget views that use WidgetShell

**Approach -- WidgetShell becomes size-aware:**

WidgetShell currently wraps content in a `VStack(spacing: 0)` with no size awareness. Add a `GeometryReader` that measures the available content area and injects a `WidgetSizeClass` into the environment.

```swift
enum WidgetSizeClass: Equatable {
    case compact    // height < 150 or width < 250
    case regular    // default
    case expanded   // height > 300 or width > 400
    
    var titleFontSize: CGFloat {
        switch self {
        case .compact: return 8
        case .regular: return 9
        case .expanded: return 11
        }
    }
    
    var bodyFontSize: CGFloat {
        switch self {
        case .compact: return 10
        case .regular: return 12
        case .expanded: return 14
        }
    }
    
    var maxVisibleItems: Int {
        switch self {
        case .compact: return 3
        case .regular: return 6
        case .expanded: return 12
        }
    }
    
    var showSecondaryInfo: Bool {
        self != .compact
    }
    
    var itemSpacing: CGFloat {
        switch self {
        case .compact: return 4
        case .regular: return 8
        case .expanded: return 10
        }
    }
}

private struct WidgetSizeClassKey: EnvironmentKey {
    static let defaultValue: WidgetSizeClass = .regular
}

extension EnvironmentValues {
    var widgetSizeClass: WidgetSizeClass {
        get { self[WidgetSizeClassKey.self] }
        set { self[WidgetSizeClassKey.self] = newValue }
    }
}
```

In `WidgetShell`, wrap the content ViewBuilder with:
```swift
GeometryReader { geo in
    let sizeClass: WidgetSizeClass = {
        if geo.size.height < 150 || geo.size.width < 250 { return .compact }
        if geo.size.height > 300 || geo.size.width > 400 { return .expanded }
        return .regular
    }()
    
    content()
        .environment(\.widgetSizeClass, sizeClass)
}
```

**CalendarWidget adaptations:**
- `.compact`: Show only next 2-3 events, smaller time text, hide duration/status column, single-line titles.
- `.regular`: Current behavior (show all today's events with time + title + duration).
- `.expanded`: Show events with more detail -- add attendee count, location, relative time ("in 45 min"), and a mini timeline bar showing the day's schedule density.

**TaskListWidget adaptations:**
- `.compact`: Show only top 3 undone tasks, smaller text, hide the "5-item soft cap" warning, abbreviate badge to just the count.
- `.regular`: Current behavior.
- `.expanded`: Show more tasks, add tag pills, show defer/follow-up dates, show waiting-on person name.

**TodoItemView adaptations:**
- `.compact`: Smaller circle (10px), tighter text, hide urgency marker if needed.
- `.regular`: Current 14px circle.
- `.expanded`: 16px circle, show full text (no lineLimit), show tags inline.

**Smooth transitions:** When the user resizes a widget via drag, the content should animate smoothly between size classes. Use `.animation(.spring(response: 0.3, dampingFraction: 0.8), value: sizeClass)` on the content wrapper. The transition between showing 3 items and 6 items should fade/slide items in/out, not pop.

### 0B. Pi Kiosk -- CSS-based responsive widget content

**Files to modify:**
- `pi-kiosk/index.html`

The kiosk uses fixed inline styles for widget dimensions. When layout presets change widget sizes, the content should adapt.

**Approach -- CSS container queries (if Chromium on Pi supports them) or JS-based resize observer:**

Option 1 (preferred, modern Chromium): Use CSS `@container` queries.
```css
.widget { container-type: size; }

@container (max-height: 120px) {
    .cal-event { padding: 2px 0; }
    .cal-time { font-size: 8px; }
    .cal-title { font-size: 8px; }
    .task-text { font-size: 9px; }
}

@container (min-height: 250px) {
    .cal-event { padding: 6px 0; }
    .cal-time { font-size: 11px; }
    .cal-title { font-size: 11px; }
    .task-text { font-size: 12px; }
}
```

Option 2 (fallback): Use `ResizeObserver` in JS to add size-class data attributes to widgets.
```javascript
const ro = new ResizeObserver(entries => {
    entries.forEach(entry => {
        const el = entry.target;
        const h = entry.contentRect.height;
        const w = entry.contentRect.width;
        el.dataset.size = h < 120 || w < 200 ? 'compact' : h > 250 || w > 350 ? 'expanded' : 'regular';
    });
});
document.querySelectorAll('.widget').forEach(w => ro.observe(w));
```
Then style with `[data-size="compact"] .cal-event { ... }`.

**Item count capping:** In `renderTasks()` and the calendar render function, check the widget's computed height and limit visible items:
- Compact: max 3 items + "N more..." overflow indicator
- Regular: max 6 items
- Expanded: show all items, scroll if needed

**Transition:** When `applyLayout()` changes widget dimensions (preset switch), animate with `transition: all 0.3s ease`. Content inside should also transition smoothly -- font sizes via CSS transition, item count changes via fade.

### 0C. Implementation order for Phase 0

| Step | What | Effort |
|------|------|--------|
| 0.1 | Define `WidgetSizeClass` enum + environment key | 15 min |
| 0.2 | Add GeometryReader to WidgetShell, inject size class | 20 min |
| 0.3 | Update CalendarWidget to read `widgetSizeClass` and adapt | 30 min |
| 0.4 | Update TaskListWidget + TodoItemView to adapt | 30 min |
| 0.5 | Update other widgets (HabitWidget, ProjectsWidget, etc.) | 45 min |
| 0.6 | Add spring animations for size class transitions | 20 min |
| 0.7 | Pi kiosk: add ResizeObserver + data-size CSS | 30 min |
| 0.8 | Pi kiosk: cap item counts per size class | 20 min |
| 0.9 | Test resize behavior across all widgets | 30 min |

**Total Phase 0 effort: ~4 hours**

---

## Phase 1: Time-Aware Calendar Display (All Surfaces)

### 1A. Auto-clear past events from view

**Files to modify:**
- `Shared/Views/Dashboard/CalendarWidget.swift` (lines 6-14)
- `pi-kiosk/index.html` (lines 333-336)

**iOS/macOS (CalendarWidget.swift):**
- Change `todaysEvents` filter: instead of showing all events from start-of-day to end-of-day, filter to only show events where `endTime > Date()` (still in progress or upcoming).
- Add a 1-minute Timer that triggers a re-render so events disappear in real time as they end. Use `TimelineView(.periodic(from: .now, by: 60))` wrapping the event list so SwiftUI auto-refreshes every 60 seconds.
- Keep showing "in progress" events (where `startTime <= now < endTime`) but mark them visually as live (see 1B).

**Pi Kiosk (index.html):**
- The kiosk calendar is currently hardcoded (line 333-336). This needs to be replaced with a dynamic data source first (see Phase 3). Once dynamic, apply the same filter: only render events where `endTime > now`.
- Add a `setInterval` every 60s that re-renders the calendar, dropping past events.

### 1B. Bold/highlight live (in-progress) events

**Files to modify:**
- `Shared/Views/Dashboard/CalendarWidget.swift` (lines 50-74)
- `Shared/Models/CalendarEvent.swift` -- add computed property
- `pi-kiosk/index.html` -- CSS + render logic

**CalendarEvent.swift -- add computed properties:**
```swift
var isLive: Bool {
    let now = Date()
    return startTime <= now && endTime > now
}

var isStartingSoon: Bool {
    let now = Date()
    let oneMinute = startTime.addingTimeInterval(-60)
    return now >= oneMinute && now < startTime
}

var minutesUntilStart: Int {
    max(0, Int(startTime.timeIntervalSinceNow / 60))
}
```

**CalendarWidget.swift -- live event styling:**
- For events where `event.isLive`: use `.bold` weight on the title, brighter accent color on the time, and a pulsing left-edge indicator (a 3px bar with a subtle glow animation).
- For events where `event.isStartingSoon`: apply a flash/pulse animation on the entire row. Use a repeating `Animation.easeInOut(duration: 0.8).repeatForever(autoreverses: true)` on the row's opacity between 0.6 and 1.0, or on the accent bar's scale. This starts 1 minute before the meeting.
- The `TimelineView` from 1A handles the refresh cadence so `isLive` / `isStartingSoon` update automatically.

**Pi Kiosk (index.html):**
- Add CSS classes: `.cal-event.live` (bolder text, brighter bar, subtle glow), `.cal-event.soon` (CSS pulse animation on the accent bar).
- In the render function, compare each event's start/end time to `Date.now()` and apply the appropriate class.
- CSS animation for `.soon`:
```css
.cal-event.soon .cal-bar {
  animation: pulse-warn 0.8s ease-in-out infinite alternate;
}
@keyframes pulse-warn {
  from { opacity: 0.5; box-shadow: 0 0 4px var(--accent); }
  to { opacity: 1; box-shadow: 0 0 10px var(--accent); }
}
```

---

## Phase 2: Tappable Events + Context Briefing (iOS/macOS)

### 2A. Make calendar events tappable

**Files to modify:**
- `Shared/Views/Dashboard/CalendarWidget.swift`
- New file: `Shared/Views/Sheets/EventBriefingSheet.swift`
- New file: `Shared/Services/MeetingPrepService.swift`
- `Shared/Models/CalendarEvent.swift` -- add optional fields

**CalendarWidget.swift:**
- Wrap each event `HStack` in a `Button` or `.onTapGesture`.
- On tap, set a `@State var selectedEvent: CalendarEvent?` which presents a `.sheet` with the `EventBriefingSheet`.

**CalendarEvent.swift -- add new optional fields for context:**
```swift
struct CalendarEvent: Identifiable, Codable {
    // ... existing fields ...
    
    // New: populated by MeetingPrepService
    var notes: String?           // from EKEvent.notes
    var url: URL?                // meeting link (Zoom, Meet, etc.)
    var organizerName: String?
    var attendeeNames: [String]?
}
```

Update `CalendarService.loadEvents()` to also pull `ekEvent.notes`, `ekEvent.url`, organizer name, and attendee display names into these fields.

### 2B. MeetingPrepService -- context gathering

**New file: `Shared/Services/MeetingPrepService.swift`**

This service gathers context for a given `CalendarEvent` and produces a `MeetingBriefing` struct.

```swift
struct ContextSource {
    let title: String
    let snippet: String       // 2-3 line summary
    let sourceType: SourceType  // .email, .calendar, .note, .slack, .unknown
    let url: URL?             // deep link to the original source
    let confidence: Double    // 0.0 to 1.0
    let timestamp: Date
}

enum SourceType: String, Codable {
    case email, calendar, note, slack, document, unknown
}

struct MeetingBriefing {
    let event: CalendarEvent
    let summary: String                    // 2-3 sentence AI-generated brief
    let contextSources: [ContextSource]    // ranked by confidence
    let overallConfidence: Double          // weighted average
    let generatedAt: Date
}
```

**Context gathering strategy (scored by confidence):**

1. **Calendar invite body/notes** (confidence: 0.95) -- direct from EKEvent.notes. Almost always relevant.
2. **Previous instances of recurring meetings** (confidence: 0.85) -- check if `ekEvent.hasRecurrenceRules`, pull notes from the last 1-2 occurrences.
3. **Email threads** -- search for emails containing the meeting title or attendee names in the last 7 days. This requires either:
   - Option A: Use the alfredo bridge to call Claude with a prompt like "find context for meeting titled X with attendees Y" (works today via existing bridge).
   - Option B: Future integration with Gmail MCP or local Mail.app search.
   - Confidence: 0.7 for title-match emails, 0.5 for attendee-match-only emails.
4. **Task Board items** -- scan `TaskBoardService` for tasks that mention the meeting title, attendee names, or related project keywords. Confidence: 0.6.
5. **Memory file** (`.claude/memory.md`) -- check People & Context and Open Threads sections for mentions of attendees or meeting topics. Confidence: 0.65.

**Confidence scoring formula:**
```
sourceConfidence = baseConfidence * recencyMultiplier * relevanceMultiplier
  where recencyMultiplier = max(0.5, 1.0 - (daysSinceSource / 14))
  where relevanceMultiplier = titleMatch ? 1.0 : attendeeMatch ? 0.7 : keywordMatch ? 0.5 : 0.3
overallConfidence = weightedAvg(top 5 sources by confidence)
```

### 2C. EventBriefingSheet -- the UI

**New file: `Shared/Views/Sheets/EventBriefingSheet.swift`**

Presented as a bottom sheet (iOS) or popover (macOS) when tapping a calendar event.

**Layout:**
```
+------------------------------------------+
| MEETING BRIEF                     [0.82] |  <-- overall confidence score
|------------------------------------------|
| Sprint Planning                          |
| 2:00 PM - 3:00 PM  ·  Zoom             |
| with: Alice, Bob, Charlie                |
|------------------------------------------|
| SUMMARY                                  |
| "Weekly sprint planning. Last session    |
|  discussed migration timeline. Alice     |
|  flagged blocker on auth service."       |
|------------------------------------------|
| CONTEXT SOURCES                          |
|                                          |
| [0.95] Calendar invite notes        ->   |
|   "Agenda: review sprint backlog..."     |
|                                          |
| [0.70] Email from Alice (2d ago)    ->   |
|   "RE: auth service migration..."        |
|                                          |
| [0.60] Task: "Review auth PR"       ->   |
|   Task Board > Today                     |
|------------------------------------------|
| [ Join Meeting ]     [ Dismiss ]         |
+------------------------------------------+
```

- Each context source row is tappable: the `->` arrow opens the source URL (email link, task board deep link, etc.).
- Confidence badges use color coding: green >= 0.8, yellow 0.5-0.79, orange < 0.5.
- "Join Meeting" button extracts the meeting URL from event.url or parses it from event.notes (look for zoom.us, meet.google.com, teams.microsoft.com patterns).
- Loading state: show a skeleton/shimmer while `MeetingPrepService` gathers context. Calendar notes load instantly; email/task search may take 1-2 seconds.

### 2D. Voice/text trigger: "get me ready for this meeting"

**Files to modify:**
- `pi-setup/alfredo-bridge.py` -- add a `/prep` endpoint or handle via Claude prompt routing
- Kiosk terminal widget -- natural language triggers

For the Pi kiosk terminal, when the user types something like "prep me for sprint planning" or "get me ready for my next meeting":
1. The bridge receives this via the existing WebSocket PTY or `/chat` endpoint.
2. Claude (running on the Pi) can call the same context-gathering logic. Since the Pi doesn't have direct EventKit access, the context flow is:
   - Bridge queries the Mac's calendar data via a new endpoint on the Mac (or uses cached calendar data pushed from the Mac to the Pi).
   - OR: The kiosk JS fetches calendar data from the Mac and passes it as context to the bridge prompt.
3. Response is formatted as a briefing and displayed in the terminal widget.

**For Phase 2, the simplest path:** have the iOS/macOS app expose calendar data via a local HTTP endpoint that the Pi can query (similar to how presence detection works). This is lower priority and can follow after the iOS/macOS implementation is solid.

---

## Phase 3: Tappable Todos + Context Briefing

### 3A. Todo tap behavior (iOS/macOS)

**Files to modify:**
- `Shared/Views/Dashboard/TaskListWidget.swift`
- `Shared/Views/Components/TodoItemView.swift`
- New file: `Shared/Views/Sheets/TaskBriefingSheet.swift`

**Current state:** `onTapTask` currently triggers `whatNext.startTask()` (focus mode). Change the tap behavior:
- **Single tap on the circle/dot:** toggle done (existing behavior via `onToggle`).
- **Single tap on the task text:** open `TaskBriefingSheet` instead of starting focus mode. Focus mode moves to a long-press or a button inside the briefing sheet.

**TaskBriefingSheet -- similar structure to EventBriefingSheet:**
```
+------------------------------------------+
| TASK CONTEXT                      [0.75] |
|------------------------------------------|
| Review auth service PR                   |
| Today  ·  @work  ·  urgent!             |
|------------------------------------------|
| RELATED CONTEXT                          |
|                                          |
| [0.85] Email from Alice (1d ago)    ->   |
|   "PR #482 ready for review..."          |
|                                          |
| [0.70] Meeting: Sprint Planning     ->   |
|   "Alice flagged blocker on auth..."     |
|                                          |
| [0.55] Slack: #engineering          ->   |
|   "auth migration thread..."             |
|------------------------------------------|
| [ Start Focus ]     [ Dismiss ]          |
+------------------------------------------+
```

**Context sources for todos:**
1. Task text keyword search across recent emails (7 days).
2. Calendar events mentioning the same keywords or project.
3. Related tasks in the same tag group.
4. Memory file references (Open Threads, Recent Decisions).
5. If `waitingPerson` is set, search for recent comms from that person.

### 3B. Pi Kiosk -- tappable todos

**Files to modify:**
- `pi-kiosk/index.html`

Currently, tapping a task dot toggles completion. Add:
- **Tap on task text:** open a briefing modal (reuse the existing modal pattern from the add-item modal). Show the task text, any related context the kiosk can gather (this will be limited on the Pi initially -- mainly the task text itself and any hardcoded relationships).
- **Future:** When the Mac-to-Pi calendar/context bridge exists, the kiosk can fetch richer context.

---

## Phase 4: Pi Kiosk Calendar -- Connect to Real Data

### 4A. Replace hardcoded calendar with live data

**Files to modify:**
- `pi-kiosk/index.html` (lines 332-336)
- `pi-kiosk/serve.py` -- add calendar proxy endpoint
- Mac-side: new lightweight HTTP server or endpoint that serves calendar JSON

**Approach:**
1. On the Mac, run a small background service (or extend an existing one) that serves `GET /calendar` returning the next 24 hours of events as JSON. Format:
```json
[
  {
    "id": "abc123",
    "title": "Sprint Planning",
    "startTime": "2026-04-09T14:00:00Z",
    "endTime": "2026-04-09T15:00:00Z",
    "location": "Zoom",
    "isLive": false,
    "isStartingSoon": false,
    "notes": "Agenda: review backlog...",
    "meetingUrl": "https://zoom.us/j/123456",
    "attendees": ["Alice", "Bob"]
  }
]
```

2. `serve.py` on the Pi gets a new `/proxy/calendar` endpoint that forwards to the Mac endpoint (similar to existing `/proxy/health`).

3. Kiosk `index.html` replaces the hardcoded array with a `fetch('/proxy/calendar')` call on a 60-second interval. Render with the same `.cal-event` markup plus `.live` and `.soon` classes.

4. Apply the same auto-clear logic: only render events where `endTime > now`.

5. Make kiosk calendar events tappable: on tap, show a modal with the event details, attendees, notes snippet, and a "PREP" button that sends a prep request to the bridge.

### 4B. Pi Kiosk -- calendar event tap + prep

When a kiosk calendar event is tapped:
1. Show a modal with event title, time, attendees, and notes.
2. "PREP" button sends a message to the Claude bridge WebSocket:
   ```json
   {"type": "input", "data": "/prep Sprint Planning\n"}
   ```
3. Claude processes and returns a briefing displayed in the terminal widget.

---

## Phase 5: Polish & Cross-Surface Consistency

### 5A. Unified MeetingPrepService interface

Ensure the same context-gathering logic works from:
- iOS/macOS tap (native, fast, direct EventKit + local search)
- Pi kiosk tap (proxied through Mac endpoint + bridge Claude call)
- Voice command (bridge processes natural language, triggers prep)

### 5B. Animation polish

- All transitions should use spring-based easing (consistent with existing momentum scroll).
- Event disappearance: fade out over 0.5s when endTime passes, then remove from DOM/view.
- Live event glow: subtle, not distracting. Match the existing accent color palette.
- Pre-meeting flash: noticeable but not alarming. 0.8s cycle, starts exactly 60s before start.
- Sheet presentation: iOS bottom sheet with `.presentationDetents([.medium, .large])`, starts at medium.

### 5C. Confidence score display guidelines

- Show as a decimal badge `[0.82]` in monospaced font, top-right of the briefing.
- Color: green (#98C379) for >= 0.8, yellow (#E5C07B) for 0.5-0.79, orange/red (#E06C75) for < 0.5.
- Individual source scores shown inline with each context source.
- If overall confidence < 0.4, show a disclaimer: "Low confidence -- limited context found. Check sources manually."

---

## Implementation Order (Recommended)

| Step | What | Files | Effort |
|------|------|-------|--------|
| S1-S6 | Critical stability fixes (injection, XSS, force unwraps) | serve.py, index.html, CalendarWidget, CalendarService, iCloudService | 45 min |
| S7-S13 | High priority stability fixes (memory leaks, race conditions, hardcoded paths) | CalendarService, WebSocketSession, DashboardView, serve.py, bridge.py | 45 min |
| BF-A | Fix scroll wheel canvas panning (macOS) | InfiniteCanvas.swift | 30 min |
| BF-B | Replace RawInputView with NSTextField (fixes TTY + scratchpad yellow icon) | TerminalTextField.swift | 30 min |
| 0 | Phase 0: Responsive widget content (see 0C table above) | WidgetShell, all widgets, kiosk | 4 hr |
| 1 | Add `isLive`, `isStartingSoon` to CalendarEvent model | CalendarEvent.swift | 15 min |
| 2 | Time-aware filtering + TimelineView in CalendarWidget | CalendarWidget.swift | 30 min |
| 3 | Live/soon visual styling (bold, pulse animation) | CalendarWidget.swift | 30 min |
| 4 | Make events tappable, show basic sheet with event details | CalendarWidget.swift, new EventBriefingSheet.swift | 45 min |
| 5 | Build MeetingPrepService (calendar notes + task search) | New MeetingPrepService.swift | 1-2 hr |
| 6 | Wire briefing service into EventBriefingSheet | EventBriefingSheet.swift | 30 min |
| 7 | Todo tap -> TaskBriefingSheet (reuse pattern from events) | TaskListWidget.swift, new TaskBriefingSheet.swift | 1 hr |
| 8 | Pi kiosk: replace hardcoded calendar with fetch | index.html, serve.py | 1 hr |
| 9 | Pi kiosk: live/soon CSS + auto-clear + tap modal | index.html | 45 min |
| 10 | Pi kiosk: PREP button -> bridge integration | index.html, bridge awareness | 30 min |
| 11 | Polish animations, confidence colors, edge cases | Various | 1 hr |

**Total estimated effort: ~15 hours** (1.5h stability + 0.5h bug fixes + 4h responsive widgets + 7-9h calendar/todo intelligence)

---

## Bug Fixes (Pre-requisite)

### BugFix A: Mouse scroll wheel should pan the canvas (macOS)

**File:** `Shared/Views/Dashboard/InfiniteCanvas.swift`

**Current state:** The scroll wheel handler exists (lines 56-71) and uses `onScrollWheel` custom modifier backed by `ScrollWheelNSView` (lines 186-197). The NSView captures `scrollWheel(with:)` events and forwards delta + phase.

**Likely issue:** The `.drawingGroup()` modifier on line 33 rasterizes the content into a Metal texture. This can interfere with hit testing. The `ScrollWheelNSView` is placed via `.background()` which means it sits behind the rasterized layer. If `.drawingGroup()` or `.clipped()` absorbs the scroll events before they reach the background NSView, the scroll handler never fires.

**Fix options (try in order):**
1. Move `.onScrollWheel` BEFORE `.drawingGroup()` in the modifier chain, or apply it to an overlay instead of background.
2. If that doesn't work, try using `.overlay(ScrollWheelView(...).allowsHitTesting(true))` instead of `.background(ScrollWheelView(...))` so the NSView sits on top for event capture.
3. Alternatively, replace the custom NSView approach with SwiftUI's native `.onScrollGesture` (available in macOS 14+) which works with the render pipeline.

**Additional:** Scroll wheel should also support horizontal scrolling (side-to-side on trackpad or tilt-wheel on mice). The current handler already receives `deltaX` and `deltaY`, so horizontal panning should work if the events are being captured. Verify that both axes move the canvas.

### BugFix B: Yellow "no entry" icon blocking keyboard input (TTY + Scratchpad)

**File:** `Shared/Views/Components/TerminalTextField.swift`

**Root cause:** The `RawInputView` implementation bypasses the Cocoa text system entirely by overriding `keyDown` on a raw `NSView`. macOS blocks this for unsigned / free-developer-account builds, showing the yellow circle-with-slash icon and refusing all keyboard input. Both `TerminalWidget` and `ScratchpadWidget` (via `QuickCaptureField`) use this same `TerminalTextField` component.

**Fix:** Replace `RawInputView` with a standard `NSTextField` wrapped in `NSViewRepresentable`. Disable all autocorrect, spell-check, and suggestion features via the proper Cocoa APIs (`isAutomaticTextCompletionEnabled`, `isContinuousSpellCheckingEnabled`, etc.) in a `controlTextDidBeginEditing` delegate method. This works through the normal text input pipeline so macOS never blocks it, while still suppressing the unwanted suggestion UI.

**Key details:**
- The `TerminalTextField` struct keeps the same public interface (`@Binding var text`, `placeholder`, `font`, `textColor`, `onSubmit`), so no changes needed in `TerminalWidget`, `QuickCaptureField`, or any other consumer.
- The custom cursor blink and `mouseDown` hit-testing in `RawInputView` are no longer needed since `NSTextField` handles all of that natively.
- Submit-on-return is handled via `NSTextFieldDelegate.control(_:textView:doCommandBy:)` checking for `#selector(NSResponder.insertNewline(_:))`.

---

### BugFix D: Scroll wheel panning (both axes)

Verify that the `onScrollWheel` handler properly translates both `deltaX` (horizontal) and `deltaY` (vertical) into canvas offset changes. The current code on lines 66-70 does apply both axes:
```swift
let rawX = offset.x + deltaX
let rawY = offset.y + deltaY
```

If the scroll events are reaching the handler (fix from BugFix A), both axes should work. Test with:
- Two-finger vertical swipe on trackpad -> canvas pans up/down
- Two-finger horizontal swipe on trackpad -> canvas pans left/right
- Mouse scroll wheel up/down -> canvas pans up/down
- Mouse tilt wheel (if available) -> canvas pans left/right

---

## Key Design Decisions

1. **Context briefing is local-first.** Calendar notes, task board, and memory file are all on-device. Email search is the only part that may need network. This keeps it fast.

2. **Confidence is transparent.** Users see exactly why each source was included and how confident the system is. No black-box summaries.

3. **Pi kiosk depends on Mac bridge for rich data.** The Pi itself has no calendar access. It needs the Mac to serve calendar data. This is the same pattern as the existing presence detection (Mac pushes/serves, Pi consumes).

4. **Focus mode is not lost.** Moving focus mode from "tap task text" to a button inside the briefing sheet preserves the feature while adding the context layer on top.

5. **No new dependencies.** Everything uses existing infrastructure: EventKit, existing bridge WebSocket, existing modal patterns on the kiosk, SwiftUI sheets on iOS/macOS.

---

## Security Notes

- The Mac calendar endpoint should only bind to localhost or the Tailscale interface, not 0.0.0.0. Pi accesses it via Tailscale IP.
- Meeting URLs parsed from event notes should be validated (only open known domains: zoom.us, meet.google.com, teams.microsoft.com).
- Email search, if implemented, should use read-only access and never expose email content beyond the snippet shown in the briefing.
- Confidence scores should never be > 1.0 or < 0.0 (clamp in the scoring function).
