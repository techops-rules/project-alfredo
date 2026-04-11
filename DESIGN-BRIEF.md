# Alfredo — Design Brief for Claude Code

> Paste this into your Claude Code project as a standing reference. Every design and UI decision for the app should be checked against this document.
>
> **Precedence rule:** If a general section and a platform-specific section (iOS / macOS) appear to conflict, the platform-specific section takes precedence. The iOS section (Section 7) is authoritative for any iOS-specific behaviour.

---

## 1. What This App Is

**App name:** Alfredo
**Mascot:** Alfred Pennyworth from Batman: The Animated Series
**Purpose:** Personal life dashboard for ADHD-inattentive type. Reads markdown files synced via iCloud. Presents them in a terminal-inspired dark UI.

**The relationship:** The app is the visual layer. Claude Code is the brain — it manages the markdown files through daily rituals (`/start`, `/sync`, `/wrap-up`). The user never edits files directly.

**Platforms:** iOS 17+ and macOS 14+ from a shared SwiftUI codebase.

---

## 2. The Core Aesthetic — Why It Matters

The terminal aesthetic (monospace fonts, dark background, ASCII borders, muted palette, grid lines) is **not decoration**. It is an ADHD accommodation:

- Monospace fonts reduce visual scanning load — everything lines up, nothing jumps around
- A dark, low-contrast palette reduces sensory overwhelm
- ASCII borders give structure without the visual weight of rounded cards and shadows
- Reduced colour use means colour can signal meaning — green = done, amber = caution

**Never** add gradients, illustrations, or high-saturation colours outside the defined accent system. Never add animations that aren't spring-based and quick (< 0.3s). Never add modals when an inline interaction will do.

---

## 3. Color System

### Base Palette

| Token | Hex | Usage |
|-------|-----|-------|
| `background` | `#080E18` | App background (or `#080C12` — nearly identical) |
| `surface` | `#080E18` @ 76% opacity | Cards, widget backgrounds |
| `textPrimary` | `#ABB2BF` | Body text |
| `textSecondary` | `#5C6370` | Labels, disabled, timestamps |
| `textEmphasis` | `#E8EAED` | Important text, clock, current task |
| `success` | `#98C379` | Done states, completed habits, positive values |
| `warning` | `#E5C07B` | Caution, paused, urgency marker |
| `danger` | `#E06C75` | Urgent tasks (use sparingly — no shame UI) |

### Accent System (User-Selectable)

The user picks one of four accents. Default is Ice. Every accent-coloured element in the UI must use these opacity variants — never raw accent at full opacity everywhere.

| Name | Hex | Default? |
|------|-----|----------|
| Ice | `#61AFEF` | ✓ |
| Coral | `#E06C75` | |
| Amber | `#E5C07B` | |
| Green | `#98C379` | |

| Variant | Opacity | SwiftUI usage |
|---------|---------|---------------|
| `accentFull` | 100% | Links, active indicators, selected state |
| `accentBorder` | 28% | Widget border strokes |
| `accentBadge` | 18% | Badge backgrounds |
| `accentTrack` | 12% | Progress bar track, inactive dots |
| `accentHeaderBg` | 5% | Widget header tint |
| `accentGrid` | 3.5% | Background grid lines |

---

## 4. Typography

**Rule:** Everything is monospaced. Use `.monospaced` font design in SwiftUI. No system fonts, no SF Pro.

| Token | Size | Weight | Usage |
|-------|------|--------|-------|
| `clockFont` | 42pt | bold | Clock widget time display |
| `statFont` | 24pt | bold | Stat values (todo count, habit count) |
| `focusTitle` | 28pt | medium | Focus mode — current task name |
| `headerFont` | `fontSize + 1` | bold | Widget section headers |
| `bodyFont` | `fontSize` | regular | Task text, habit names, body content |
| `captionFont` | `fontSize - 2` | regular | Timestamps, small labels |
| `tinyLabel` | 9pt | bold | Widget title bar labels, badge text |

`fontSize` is user-adjustable: **11pt / 13pt (default) / 15pt**. All relative tokens scale with it.

Section headers use `letterSpacing: 2pt`.

---

## 5. Border & Grid System

### ASCII Widget Borders

Every widget has an ASCII-character border overlay. The user can pick from 8 styles:

| Style | Corner chars | Horizontal | Vertical |
|-------|-------------|-----------|---------|
| `line` | `┌ ┐ └ ┘` | `─` | `│` |
| `round` | `╭ ╮ ╰ ╯` | `─` | `│` |
| `heavy` | `┏ ┓ ┗ ┛` | `━` | `┃` |
| `double` | `╔ ╗ ╚ ╝` | `═` | `║` |
| `ascii` | `+ + + +` | `-` | `\|` |
| `block` | `▛ ▜ ▙ ▟` | `▀` / `▄` | `▌` / `▐` |
| `dots` | `· · · ·` | `·` | `·` |
| `stars` | `* * * *` | `*` | `*` |

Border stroke: `accent @ 28%` opacity.
Border width: 1pt (default), 2pt, or 3pt — user-selectable.

### Border Stroke Styles
`solid` / `dashed [8,4]` / `dotted [2,3]` / `double` — user-selectable.

### Corner Radii
- Progress bars: 3pt
- Buttons and inputs: 4pt
- Widgets: 6pt
- Panels and overlays: 8pt

### Background Grid
- Spacing: 80pt
- Stroke: 0.5pt
- Colour: accent @ 3.5% opacity
- Drawn as a `Canvas` or `Path` overlay on the canvas background layer

---

## 6. The Infinite Canvas — Core Interaction Model

This is the heart of the app on both platforms.

### What it is

A 2D infinite canvas (world space) that is larger than the screen. The user pans around the canvas to find their widgets, which sit at fixed world-space coordinates. Widgets can be moved, resized, and collapsed.

### World Dimensions

| | macOS | iOS |
|--|-------|-----|
| World width | 2800pt | 2800pt |
| World height | 1900pt | 1900pt |
| Default viewport | 1280 × 820pt | screen size |
| Default pan position | (0, 0) — top-left | (0, 0) — top-left |

Main dashboard panel is always placed at top-left so the user opens to a useful view.

### Pan Behaviour

- Pan is clamped: the user cannot scroll past the world edges
- On macOS: two-finger trackpad scroll (wheel events) — `deltaX` / `deltaY` applied directly
- On macOS: click-drag on empty canvas space (not on widgets)
- On iOS: **single-finger drag** on empty canvas space
- **Momentum:** On release, pan continues with exponential decay (velocity × 0.88 per frame via SwiftUI's animation system)

### Zoom (both platforms)
- **macOS:** two-finger trackpad pinch
- **iOS:** standard `MagnificationGesture` (pinch with two fingers)
- Range: 0.5× – 2.0× on both platforms
- Applied as a `scaleEffect` / `CGAffineTransform` on the world layer
- Zoom level selector also available in settings panel (macOS) / bottom sheet (iOS)
- Current zoom level is persisted per platform in `WidgetLayout` or `UserDefaults`

### Widget Interaction

Widgets are NOT interactive by default when the user is panning. To interact with a widget (drag it, resize it), the user must enter **Edit Mode**:

- **macOS:** click the ⋮ or grip handle on the widget header, OR press a global "Edit Layout" toggle
- **iOS:** **long-press** on empty canvas space → enters Edit Mode → all widgets show resize handles and drag grips → finger-drag to move → drag resize handle to resize → tap anywhere outside Edit Mode to exit

### Widget Snap Grid

- Snap to 20pt grid when dragging or resizing
- Visual snap indicator (brief highlight of grid lines) on release

### Widget Layout Persistence

Each widget's `(x, y, width, height, isCollapsed)` is stored in `WidgetLayout` model, persisted to iCloud alongside the markdown files.

---

## 7. iOS — THE KEY CHANGE

**Current state:** iOS uses a 4-tab layout (Home, Tasks, Scratchpad, More). This must be replaced.

**Target state:** iOS uses the same infinite canvas widget system as macOS.

### Remove
- `iOS/iOSApp.swift` tab bar setup
- `iOS/TabViews/` — all four tab views (Home, Tasks, Scratchpad, More)

### Replace with
A single `iOSCanvasView` that renders the same `InfiniteCanvas` component as macOS, adapted for touch.

### iOS Gesture Specification

```swift
// Pan — single finger on empty canvas
DragGesture(minimumDistance: 5, coordinateSpace: .global)
    .onChanged { value in
        canvasOffset = clampedOffset(
            base: dragStartOffset,
            translation: value.translation
        )
    }
    .onEnded { value in
        let velocity = value.velocity
        withAnimation(.interactiveSpring(response: 0.6, dampingFraction: 0.7)) {
            canvasOffset = clampedOffset(
                base: canvasOffset,
                translation: CGSize(
                    width: velocity.width * 0.15,
                    height: velocity.height * 0.15
                )
            )
        }
    }

// Zoom — pinch on canvas
MagnificationGesture()
    .onChanged { scale in
        canvasScale = clamp(baseScale * scale, min: 0.5, max: 2.0)
    }

// Widget edit mode — long press on empty canvas
LongPressGesture(minimumDuration: 0.5)
    .onEnded { _ in
        isEditMode = true
        // Haptic feedback: UIImpactFeedbackGenerator .medium
    }

// Widget drag — only in edit mode
DragGesture()  // on widget
    .onChanged { value in
        guard isEditMode else { return }
        widgetPosition = snapToGrid(
            base: widgetStartPosition,
            translation: value.translation,
            gridSize: 20
        )
    }
```

### iOS Layout Considerations

- **Status bar area:** leave safe area inset at top, canvas starts below it
- **Home indicator:** respect safe area at bottom — no widgets placed in that zone by default
- **Widget sidebar** (visibility toggles): appears as a bottom sheet on iOS (not a side panel)
- **Settings/theme panel:** same bottom sheet pattern

### What replaces the tab content

All tab content becomes widgets on the canvas:

| Former tab | Becomes widget(s) |
|-----------|-------------------|
| Home (breadcrumb + today tasks) | BreadcrumbBar widget + TaskList widget |
| Tasks (grouped list) | TaskList widget (expanded) |
| Scratchpad | Scratchpad widget |
| More (habits, goals, projects) | Habits widget + Goals widget + Projects widget |

### Default iOS layout (top-left origin):

```
(0,0)        TaskList — today       (320,0)   BreadcrumbBar / WhatNext
(0,280)      Calendar               (320,120)  QuickCapture
(0,520)      Habits                 (320,340)  Scratchpad
(600,0)      Goals                  (600,280)  Projects
```

---

## 8. Widget Inventory

All widgets share the `WidgetShell` container. See Section 9 for shell spec.

| Widget | Min size (pt) | Preferred size | Collapsed shows | Expanded shows | Collapse behaviour |
|--------|--------------|----------------|-----------------|----------------|-------------------|
| Clock | 200 × 80 | 260 × 120 | Time (HH:MM) | Time + date + day | Shrinks to header with time in badge |
| TodayBar | 280 × 60 | 400 × 80 | 4 stat numbers inline | 4 stat cards with labels + sub-labels | Collapses to one-line stat strip |
| TaskList | 240 × 200 | 340 × 400 | Count badge (e.g. "3/8") | Full scrollable task list, work + personal tabs | Header shows count, body hides |
| Calendar | 280 × 160 | 360 × 300 | Next event name + time | Week strip (7 days) + event list below | Header shows next event |
| Goals | 200 × 160 | 300 × 260 | Count + highest % | Goal names + progress bars | Header shows count |
| Habits | 200 × 160 | 300 × 280 | Done/total (e.g. "2/6") | Habit rows with streak counts + toggle | Header shows ratio |
| Projects | 240 × 180 | 340 × 280 | Active project count | Project names + % bars + status + due date | Header shows count |
| Scratchpad | 240 × 200 | 340 × 360 | Entry count | Scrollable list with ">" prefix + quick capture field | Header shows count |
| Stats | 300 × 200 | 460 × 280 | 2 key numbers | 6-card grid (todos, habits, commits, focus hrs, open PRs, events) | Header shows 2 values |
| Minimap | 140 × 100 | 180 × 130 | Always visible | Thumbnail of full canvas with viewport indicator | N/A — no collapse |
| AI Chat | 280 × 200 | 360 × 400 | Last AI message | Full chat thread + ">" quick-input field | Header shows last message truncated |

---

## 9. WidgetShell Specification

Every widget is wrapped in `WidgetShell`.

```
┌─ [▼] WIDGET TITLE          [badge]  [zone] ─┐
│                                              │
│   Content area (12pt padding all sides)      │
│                                              │
└──────────────────────────────────────────────┘
```

### Header (36pt tall)
- **Left:** chevron ▼ / ▶ in accent, 10pt, opacity 0.7
- **Title:** uppercase, 9pt bold, accent colour, letterSpacing 2pt
- **Badge** (optional): accent @ 18% bg, accent text, 10pt, 7pt h-padding
- **Zone label** (optional): textSecondary, 9pt, right-aligned
- **Header background:** accent @ 5%
- **Header bottom border:** accent @ 15%

### Body
- **Padding:** 8pt top, 12pt left/right, 8pt bottom
- **Background:** `#080E18` @ 76%
- **Backdrop blur:** 18pt
- **Overflow:** scroll vertically, clip horizontally

### Animation
- Collapse/expand: spring — response 0.3s, damping 0.8
- Height animates from full to 36pt (header only)

### Edit Mode
- **Drag handle** (⠿) top-left corner
- **Resize handle** (◢) bottom-right corner
- Subtle highlight ring around widget
- Tap outside to exit edit mode

---

## 10. Key Component Specs

### BreadcrumbBar
- Fixed at top of viewport (not on canvas)
- Shows: `> SUGGESTED NEXT: [task text]`
- Tap → "WHAT'S NEXT?" modal with Skip / Start buttons
- Bottom border: 1pt accent line

### QuickCaptureField
- `>` prefix in bold accent
- Background: `#080E18` @ 50%, border: accent @ 28%, 4pt radius
- Auto-focuses on tap; on submit appends to Scratchpad.md

### TodoItemView
- 14×14pt circle: filled `#98C379` if done, stroked accent @ 50% if not
- Done: textSecondary + strikethrough + 45% opacity (carry-forward, not hidden)
- Urgency marker: `!` in amber `#E5C07B` — not red, no shame

### HamburgerMenu / Settings Panel
- **macOS:** 260pt side panel from right
- **iOS:** bottom sheet, 80% screen height
- Contains: 4 accent circles (18pt), border style grid, border width, font size, zoom (macOS)

### AsciiMascot (Alfred)
- 4 moods: idle / loading / happy / thinking
- Frame-based ASCII animation, spring easing
- No images — characters only

---

## 11. App Icon

ASCII art only — no SVG, no images.

**Background** (dim ~22%):
```
       /\         /\
    __/  \_______/  \__
   /   /\         /\   \
  /   /  \_______/  \   \
 |   /             \   |
  \ /───────────────\ /
   '─────────────────'
```

**Foreground** (full brightness + glow):
```
──◆──
```

- Accent: `#4F9ED4` (ice blue)
- Background: `#010306`
- Rounded square, 44pt radius at 260×260pt
- Scanline overlay: 7% opacity, 3pt repeat

---

## 12. Boot Screen

- **Duration:** 1.8s
- Full-screen `#080E18` background
- ASCII logo animates in
- Boot log scrolls fake system lines
- Scanline sweep top-to-bottom
- 1–2 random glitch frames during sweep
- Fades to canvas on completion

---

## 13. ADHD Design Principles — Non-Negotiable

1. **Zero friction.** One tap or less. No confirmation dialogs for minor actions.
2. **Push, don't pull.** BreadcrumbBar always shows suggested next task. User never goes looking.
3. **Soft cap at 5 today items.** Amber badge if exceeded. Signal only — no pressure.
4. **Smallest first step.** WhatNext: overdue → urgent → fewest words → file order.
5. **No shame, ever.** No "overdue" labels. Tasks carry forward. Incomplete ≠ failure.
6. **Graceful degradation.** Collapsing widgets reduces load. Edit mode always reversible.
7. **Celebrate wins.** Done items stay visible (dimmed, struck) until archived.
8. **Terminal aesthetic is intentional.** No gradients, no illustrations. Reduced visual complexity is the feature.

---

## 14. What "Done" Looks Like

### macOS
- [ ] Canvas panning smooth with momentum
- [ ] All 10+ widgets draggable/resizable, 20pt snap
- [ ] Widget layout persists (WidgetLayout → iCloud)
- [ ] Settings: accent, border style/width, font size, zoom
- [ ] Boot screen on launch
- [ ] BreadcrumbBar sticky at top

### iOS (primary new work)
- [ ] 4-tab layout removed entirely
- [ ] iOSCanvasView with infinite canvas + all widgets
- [ ] Single-finger drag pans with momentum
- [ ] Pinch-to-zoom works
- [ ] Long-press → Edit Mode + haptic
- [ ] Edit Mode: widgets draggable with resize handles
- [ ] Bottom sheet for settings
- [ ] BreadcrumbBar fixed at top of screen
- [ ] Widget layout persists to iCloud

### Shared
- [ ] Shared WidgetShell — no platform-specific wrappers
- [ ] WidgetLayout stores position/size/collapsed per widget per platform
- [ ] Theme persists to UserDefaults or iCloud KV

---

## 15. File Map

```
Shared/
  App/ProjectAlfredoApp.swift    — entry point, branches macOS vs iOS
  Models/
    WidgetLayout.swift           — x, y, w, h, isCollapsed, widgetId, platform
    Task / Goal / Habit / CalendarEvent / Memory
  Services/
    TaskBoardService.swift       — reads/writes Task Board.md
    WhatNextEngine.swift         — task prioritisation
    CalendarService.swift        — EventKit
    iCloudService.swift          — sync + fallback
    ScratchpadService.swift
  Views/
    Canvas/
      InfiniteCanvas.swift       — shared canvas engine
      WidgetShell.swift          — shared widget container
      CanvasEditMode.swift       — drag/resize/snap logic
    Widgets/
      ClockWidget / TaskListWidget / CalendarWidget / HabitsWidget
      GoalsWidget / ProjectsWidget / ScratchpadWidget
      StatsWidget / MinimapWidget / AIWidget / TodayBarWidget
    Components/
      TodoItemView / QuickCaptureField / BreadcrumbBar
      HamburgerMenu / ProgressDots / AsciiMascot
    Focus/
      FocusModeView.swift
  Theme/
    Colors.swift / Typography.swift / Borders.swift
iOS/
  iOSApp.swift                   — launches iOSCanvasView, no TabView
  iOSCanvasView.swift            — InfiniteCanvas + iOS gesture layer
macOS/
  MacApp.swift / MacCanvasView.swift / MenuBarManager.swift
```

---

## 16. Technical Constraints

- **SwiftUI only** — no UIKit
- **Markdown files** are the data layer — no Core Data, no SQLite
- **iCloud Documents** — container `iCloud.com.projectalfredo.app`
- **@Observable** state management
- **EventKit** for calendar
- **iOS 17+ / macOS 14+**
