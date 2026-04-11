# Implementation Plan: Calendar & Todo Intelligence Layer

**Goal:** Make calendar events and todos interactive, time-aware, and context-rich across all alfredo surfaces (iOS, macOS, Pi kiosk). Events auto-clear after they pass, live events get visual emphasis with a pre-meeting flash, and tapping any event or todo triggers a context briefing with confidence scores. Widget content should scale responsively to the container size the user sets.

## What's already implemented (verified 2026-04-10)

These features exist in the codebase and work. Do NOT re-implement:
- **CalendarWidget** -- TimelineView (60s refresh), `activeEvents(at:)` filters past events, `isLive`/`isStartingSoon` computed properties, PulsingBar animation, "NOW" / "in Xm" labels, tap-to-expand (collapsed/brief/full), long-press opens EventBriefingSheet
- **EventBriefingSheet** -- loads MeetingBriefing from MeetingPrepService, shows confidence scores, context sources, shimmer loading state
- **TaskBriefingSheet** -- shows task context, related sources, confidence scoring
- **MeetingPrepService** -- gathers context from calendar notes, recurrence history, task board, memory files
- **BriefingScheduler** -- 8am morning briefing, 25min pre-meeting notifications, runs on app launch
- **TaskListWidget** -- tap text opens TaskBriefingSheet, circle toggles done, long-press triggers focus mode
- **TerminalTextField** -- NSTextField replacement for RawInputView (BF-B, done)
- **InfiniteCanvas scroll wheel** -- onScrollWheel positioned before drawingGroup (which was removed entirely)
- **Pi kiosk security** -- auth tokens on system endpoints, XSS fixed (textContent), command injection fixed (subprocess array)
- **Pi kiosk live calendar** -- `/proxy/calendar` endpoint with fetch in index.html

## What remains to be built

1. **Stability fixes S8-S9** -- WebSocket race condition, @State/@StateObject verification (see below)
2. **Phase 0: Responsive widget content** -- WidgetSizeClass environment, adaptive font/item counts
3. **Phase 5: Polish** -- animation consistency, cross-surface parity
4. **Apple Mail integration** -- email context in briefings (future)
5. **Back-to-back meeting brief bundling UI** (future)

---

## Pre-Work: Stability Audit (Claude Code should run this first)

Codebase scan turned up issues that should be fixed before building new features on top. Grouped by priority.

### Already fixed (verified 2026-04-10)

These were identified in the audit but have already been resolved:
- ~~S1: Command injection in serve.py~~ -- now uses subprocess array format
- ~~S2: XSS in index.html~~ -- task text uses textContent
- ~~S3: Unauthenticated endpoints~~ -- Bearer token auth + localhost check added
- ~~S4-S6: Force unwrap crashes~~ -- replaced with guard let
- ~~S7: CalendarService observer leak~~ -- deinit with removeObserver added
- ~~S10: Subprocess hangs~~ -- Popen calls use proper args
- ~~S11: Content-Length~~ -- MAX_BODY = 1MB cap added
- ~~S12: Bare except clauses~~ -- changed to `except Exception:`
- ~~S13: Hardcoded paths~~ -- uses `os.path.expanduser("~")`

### Remaining stability issues (fix before/during feature work)

| # | File | Issue |
|---|------|-------|
| S8 | `WebSocketSession.swift:79-86,228-232` | **Race condition** -- `receiveTask` and `pingTask` can be nil'd in `cleanup()` while `receiveLoop()` is running. Fix: cancel tasks before nilling, or add a lock. |
| S9 | `DashboardView.swift:5-6` | **@State for @Observable classes** -- `TaskBoardService()` and `ScratchpadService()` created as `@State`. With `@Observable` (not `ObservableObject`), `@State` is actually the correct pattern in modern SwiftUI. Verify these use `@Observable` (not `ObservableObject`) and if so, this is fine. If they use `ObservableObject`, switch to `@StateObject`. |

### INFO (fix opportunistically)

| # | File | Issue |
|---|------|-------|
| S14 | `index.html` | localStorage quota not handled, silent data loss on `setItem()` |
| S15 | `index.html` | 2-second polling race between settings.html writes and index.html reads |
| S16 | `TerminalWidget.swift` | URLSession HTTP request not cancellable if view is dismissed |
| S17 | `WebSocketSession.swift` | UserDefaults access uses unsafe casting pattern, no type validation |
| S18 | `index.html` | fetch() calls with `.catch(()=>{})` silently swallow all errors |

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

## ~~Phase 1: Time-Aware Calendar Display~~ -- DONE

Already implemented in CalendarWidget.swift: TimelineView 60s refresh, `activeEvents(at:)` filters past, `isLive`/`isStartingSoon` computed properties, PulsingBar animation, NOW/in-Xm labels. Kiosk has live data via `/proxy/calendar`.

See CalendarWidget.swift lines 9-17 (filtering), 132-153 (live/soon styling), 210-225 (PulsingBar).

---

## ~~Phase 2: Tappable Events + Context Briefing~~ -- DONE

Already implemented: CalendarWidget tap-to-expand (collapsed/brief/full states), long-press opens EventBriefingSheet, MeetingPrepService gathers context from calendar notes/recurrence/task board/memory, confidence scoring, TaskBriefingSheet with same pattern. BriefingScheduler handles 8am morning brief + 25min pre-meeting notifications.

Key files: EventBriefingSheet.swift, TaskBriefingSheet.swift, MeetingPrepService.swift, BriefingScheduler.swift

---

## ~~Phase 3: Tappable Todos + Context Briefing~~ -- DONE

Already implemented: TaskListWidget tap-text opens TaskBriefingSheet, circle toggles done, long-press triggers focus mode.

---

## ~~Phase 4: Pi Kiosk Calendar -- Connect to Real Data~~ -- DONE

Already implemented: `/proxy/calendar` endpoint in serve.py, `fetch('/proxy/calendar')` in index.html, live/soon CSS classes, auth on system endpoints.

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

## Implementation Order (Remaining Work)

| Step | What | Files | Effort |
|------|------|-------|--------|
| S8 | Fix WebSocket task cleanup race condition | WebSocketSession.swift | 15 min |
| S9 | Verify @State vs @StateObject correctness for service objects | DashboardView.swift | 15 min |
| Phase 0 | Responsive widget content (see 0C table above) | WidgetShell, all widgets, kiosk | 4 hr |
| Phase 5 | Polish: animation consistency, cross-surface parity, edge cases | Various | 1 hr |

**Total remaining effort: ~5.5 hours** (0.5h stability + 4h responsive widgets + 1h polish)

---

## Bug Fixes (All Resolved)

All pre-requisite bug fixes have been completed:
- **BF-A: Scroll wheel panning (macOS)** -- Fixed. `onScrollWheel` positioned before `.drawingGroup()` (which was removed entirely). Both axes work.
- **BF-B: Yellow "no entry" icon (TTY + Scratchpad)** -- Fixed. `TerminalTextField` replaced `RawInputView` with `NSTextField` + `NSViewRepresentable`.
- **BF-D: Scroll wheel both axes** -- Fixed along with BF-A. `deltaX` and `deltaY` both translate to canvas offset.

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
