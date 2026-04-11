# Project Alfredo - Design Briefing for Replit

## What This Is

Project Alfredo is a cross-platform (iOS 17+ / macOS 14+) SwiftUI app that serves as a personal task dashboard for someone with ADHD-inattentive type. It reads markdown files (Task Board.md, Scratchpad.md, Memory, etc.) synced via iCloud and presents them in a terminal-inspired dark UI.

The app works alongside a Claude Code AI assistant that manages the markdown files through daily rituals (/start, /sync, /wrap-up). The app is the visual layer; Claude is the brain.

**Goal of this refresh:** I want detailed, actionable design and UI/UX recommendations I can bring back to my code editor for implementation. I need specific SwiftUI code changes, not vague suggestions.

---

## Current Architecture

### Platforms
- **macOS:** Infinite canvas dashboard with draggable/resizable widgets. Window min 1200x700, default 1400x800.
- **iOS:** 4-tab interface (Home, Tasks, Scratchpad, More). Standard tab bar navigation.

### Tech Stack
- SwiftUI (no UIKit)
- iCloud Documents for storage (local fallback)
- EventKit for calendar
- All data stored as markdown files, parsed at runtime
- @Observable pattern for state management

### File Structure
```
Shared/
  App/ProjectAlfredoApp.swift    (entry point, platform branching)
  Models/                        (Task, Goal, Habit, CalendarEvent, Memory, Scratchpad, WidgetLayout)
  Services/                      (TaskBoard, WhatNext, Calendar, iCloud, Markdown parser, Memory, Scratchpad)
  Views/
    Components/                  (9 reusable pieces)
    Dashboard/                   (11 dashboard widgets + infinite canvas)
    Focus/                       (distraction-free mode)
  Theme/                         (colors, fonts, accent system)
iOS/
  iOSApp.swift                   (tab setup)
  TabViews/                      (Home, Tasks, Scratchpad, More)
macOS/
  MacApp.swift                   (window + dashboard)
  MenuBarManager.swift
```

---

## Design System

### Color Palette (Dark theme, terminal-inspired)

| Token | Hex | RGB | Usage |
|-------|-----|-----|-------|
| background | #080E18 | (8, 14, 24) | App background |
| surface | #080E18 @ 76% | Same + opacity | Cards, widget backgrounds |
| textPrimary | #ABB2BF | (171, 178, 191) | Body text |
| textSecondary | #5C6370 | (92, 99, 112) | Labels, disabled text |
| textEmphasis | #E8EAED | (232, 234, 237) | Important text, highlights |
| success | #98C379 | (152, 195, 121) | Done states, positive |
| warning | #E5C07B | (229, 192, 123) | Caution, paused |
| danger | #E06C75 | (224, 108, 117) | Urgent, errors |

### Accent Colors (User-selectable, 4 options)

| Name | Hex | Default? |
|------|-----|----------|
| Ice | #61AFEF | Yes |
| Coral | #E06C75 | |
| Amber | #E5C07B | |
| Green | #98C379 | |

Each accent has opacity variants:
- `accentFull`: 100% (links, active elements)
- `accentBorder`: 28% (widget borders)
- `accentBadge`: 18% (badge backgrounds)
- `accentTrack`: 12% (progress track, inactive states)
- `accentHeaderBg`: 5% (widget header tint)
- `accentGrid`: 3.5% (background grid lines)

### Typography (All monospaced)

| Token | Size | Weight | Usage |
|-------|------|--------|-------|
| clockFont | 42pt | bold | Clock widget time |
| statFont | 24pt | bold | Stat values |
| focusTitle | 28pt | medium | Focus mode task name |
| headerFont | fontSize+1 | bold | Section headers |
| bodyFont | fontSize | regular | Body text |
| captionFont | fontSize-2 | regular | Small labels |
| tinyLabel | 9pt | bold | Widget titles, badge text |

- **fontSize** is user-adjustable: 11pt, 13pt (default), or 15pt
- All fonts use `.monospaced` design
- Section headers use 2pt letter spacing

### Border System

- ASCII-art borders on widgets (8 character styles: line, round, heavy, double, ascii, block, dots, stars)
- Each style defines: top-left, top-right, bottom-left, bottom-right corners + horizontal + vertical edges
- Border styles: solid, dashed [8,4], dotted [2,3], double
- Border width: 1pt (default), 2pt, 3pt
- Corner radius: 3pt (progress bars), 4pt (buttons/inputs), 6pt (widgets), 8pt (panels)

### Grid Background
- 80pt spacing
- 0.5pt line width
- Accent color @ 3.5% opacity

---

## Current Components

### WidgetShell (Container for all dashboard widgets)
- Collapsible header with chevron
- Title in uppercase, badge count, zone indicator
- Header background: accent @ 5%
- Content area: 12pt padding
- Background: surface + ultraThinMaterial @ 30%
- ASCII border overlay with theme-selected characters
- Spring animation for collapse: response 0.3, damping 0.8

### TodoItemView (Task item)
- 14x14pt circle indicator (filled green if done, stroked gray if not)
- Task text with optional strikethrough when done
- Urgency "!" marker in danger color
- 10pt spacing, 2-line limit

### QuickCaptureField (Text input)
- ">" prefix in accent color (bold)
- Background @ 50% opacity
- Border: accent @ 28%, corner radius 4pt
- Auto-focus on appear

### BreadcrumbBar (Current task indicator)
- Shows current task from WhatNext engine
- "SUGGESTED NEXT" modal with Skip/Start buttons
- Bottom border accent line

### HamburgerMenu (Settings panel)
- 260pt wide panel
- Accent color picker (4 circles, 18x18pt)
- Border character style grid
- Border style, width, font size selectors
- Zoom selector (macOS only)
- Spring animation, scale+opacity transition

### ProgressDots
- 5 dots @ 8x8pt, 4pt spacing
- Filled: accent, unfilled: accent @ 12%

### AsciiMascot
- Animated ASCII art character
- 4 moods: idle, loading, happy, thinking
- Frame-based animation with spring easing

---

## Current Screens

### macOS Dashboard
- Infinite canvas (2800x1200pt world, scrollable with momentum)
- Draggable, resizable widgets snapping to 20pt grid
- Widgets: Clock, TodayBar (4 stats), TaskList, Calendar (week strip + events), Goals, Habits, Projects, Scratchpad, Stats (6-card grid), Minimap
- Widget sidebar (220pt) for visibility toggles and drag reorder
- Boot screen on launch (ASCII animation, 1.8s)
- Focus mode (full-screen overlay for single task)

### iOS Tabs

**Home Tab:**
- Breadcrumb bar at top (current task)
- TODAY section: task list with toggle
- UPCOMING section: next 3 calendar events
- Quick capture field at bottom

**Tasks Tab:**
- Grouped list by section (Today, Soon, Later, Waiting, Inbox, Done)
- Section headers: uppercase, accent color, letter-spaced

**Scratchpad Tab:**
- Quick capture input at top
- Scrolling list of captured items with ">" prefix

**More Tab:**
- Habits widget, Goals widget, Projects widget
- Theme control panel

---

## Data Models

### AppTask
```
id: UUID
text: String
isDone: Bool
isUrgent: Bool
section: .today | .soon | .later | .waiting | .deferred | .agenda | .inbox | .done | .reference
scope: .work | .personal
tags: [String]
deferDate: Date?
followUpDate: Date?
waitingPerson: String?
fileLineIndex: Int?
displayText: String (computed - stripped of @scope and ! markers)
```

### CalendarEvent
```
id: String
title: String
startTime: Date
endTime: Date
location: String?
isAllDay: Bool
durationMinutes: Int (computed)
timeString: String (computed - "h:mm a" or "All day")
relativeTimeString: String (computed - "now", "in X min")
```

### MemoryFile
```
now: [String]
openThreads: [String]
parked: [String]
peopleAndContext: [String]
recentDecisions: [String]
```

### Goal
```
id: UUID
name: String
targetDate: String
progressPercent: Int
category: .financial | .reading | .sideProject
```

### Habit
```
id: UUID
name: String
isDoneToday: Bool
```

---

## Key Services

### WhatNextEngine (Task suggestion algorithm)
Priority order:
1. Defer date has passed (overdue first)
2. Is urgent (urgent first)
3. Fewest words (smallest task first - ADHD: easy wins build momentum)
4. File order (earlier in file first)

Filters out: done tasks, non-today tasks, skipped tasks.

### TaskBoardService
- Reads/writes `Task Board.md`
- Parses markdown with checkbox syntax `- [ ]` / `- [x]`
- Extracts: scope (@work/@personal), urgency (!), defer dates [defer:MMDDYY], tags

### CalendarService
- EventKit integration (requests full access)
- Loads 7 days of events
- Currently also has sample data fallback

### iCloudService
- Container: `iCloud.com.projectalfredo.app`
- Fallback: `~/Documents/ProjectAlfredo/`
- Seeds default content on first run

---

## ADHD Design Principles (Non-Negotiable)

These must be preserved in any redesign:

1. **Zero friction.** Every interaction should be one tap or less. No multi-step workflows.
2. **Push, don't pull.** The app surfaces what matters. The user never goes looking.
3. **Soft cap at 5 today items.** Visual warning if exceeded. Prevents overwhelm.
4. **Smallest first step.** The WhatNext engine prioritizes small tasks. Easy wins build momentum.
5. **No shame, ever.** No "overdue" labels, no red warnings on incomplete items. Tasks "carry forward."
6. **Graceful degradation.** If overwhelmed, the interface should simplify, not add pressure.
7. **Celebrate wins.** Done items are visible and acknowledged, not hidden.
8. **Terminal aesthetic is intentional.** Monospace fonts and dark theme reduce visual noise for ADHD. The reduced visual complexity is a feature.

---

## What I Want From This Refresh

I'm looking for recommendations on:

1. **iOS tab layout** - Is 4 tabs right? Should Home be restructured? What about the More tab being a dumping ground?
2. **Information density** - Am I showing enough/too much on the Home tab?
3. **Task interaction patterns** - Swipe actions? Long-press? Better completion feedback?
4. **Calendar integration** - Better way to show today's schedule alongside tasks?
5. **Visual hierarchy** - Are the most important things (next task, next meeting) prominent enough?
6. **Widget/dashboard polish** - macOS canvas improvements, better widget designs
7. **Animations and transitions** - Where do micro-interactions help vs. distract?
8. **Accessibility** - Dynamic type, VoiceOver, reduced motion support
9. **Color and contrast** - Is the current palette WCAG compliant? Improvements?

**Constraints:**
- Must stay SwiftUI (no UIKit)
- Must keep monospace/terminal aesthetic (it's an ADHD accommodation, not just style)
- Must read from markdown files (the data layer is fixed)
- Must support both iOS and macOS from shared codebase
- No shame-based UI patterns (no red "overdue" badges, no guilt counters)

**What I need back:**
- Specific SwiftUI view code or modifiers to change
- File paths for what to modify
- Before/after descriptions
- Reasoning tied to ADHD UX principles
