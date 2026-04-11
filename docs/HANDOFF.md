# Alfredo — Peer Review Handoff

> For: Codex (or any AI agent with repo access)
> From: Claude Code (Opus 4.6)
> Date: 2026-04-11
> Repo: `techops-rules/project-alfredo`

---

## What this project is

**Alfredo** is a personal ADHD operating system for Todd. It runs on three surfaces simultaneously:

| Surface | Tech | Location |
|---------|------|----------|
| iOS app | SwiftUI, infinite canvas | `Shared/`, `iOS/` |
| macOS app | SwiftUI, same codebase | `Shared/`, `macOS/` |
| Pi kiosk | HTML/JS, 1024×600 screen | `pi-kiosk/` |

The dashboard shows: calendar events, task lists, a terminal widget (CLAUDE.TTY) bridging to Claude Code on the Pi, weather timeline, projects, and a scratchpad. It is deeply time-aware — events auto-clear, live meetings pulse, morning briefings pre-load with confidence-scored context.

---

## Current state (v0.48.0, 2026-04-11)

### What's working and shipped

- iOS infinite canvas with pan/zoom, long-press edit mode, widget drag/resize
- Calendar widget: time-aware (past events clear, live events glow, 25min pre-meeting pulse)
- Tappable events → MeetingBriefingSheet with context + confidence scores
- Tappable tasks → TaskBriefingSheet; long-press = focus mode
- MeetingPrepService, BriefingScheduler (8am daily + 25min pre-meeting)
- ALFREDO.TTY terminal widget — HTTP bridge to Claude Code at pihub.local:8420
- Weather timeline widget — sun/moon dome arc, hourly forecast, Open-Meteo API
- Pi kiosk: 5 context-aware modes (work/meeting/focus/night/weekend), weather arc, layout editor
- Pi kiosk security: auth tokens on system endpoints, XSS fixed, command injection fixed
- Git-based deployment: `pi-kiosk/deploy.sh` → rsync to Pi → systemctl restart

### Uncommitted changes in working tree (minor, not yet committed)

- `Shared/Models/WidgetLayout.swift` — modified
- `Shared/Views/Dashboard/CalendarWidget.swift` — modified
- `Shared/Views/Dashboard/DashboardView.swift` — modified
- `Shared/Views/Dashboard/HotlistWidget.swift` — modified
- `Shared/Views/Dashboard/WeatherWidget.swift` — modified
- `Shared/Views/Dashboard/WidgetLayout.swift` — new untracked file

These appear to be in-progress layout work. **Do not commit these without understanding what they are** — check `git diff` first.

---

## What needs to be built (priority order)

### 1. Stability: S8 — WebSocket race condition (HIGH)
**File:** `Shared/Services/WebSocketSession.swift:79-86, 228-232`

`receiveTask` and `pingTask` can be nil'd in `cleanup()` while `receiveLoop()` is running. Fix: cancel tasks before nilling, or guard with a lock. This can cause a crash in the ALFREDO.TTY terminal widget.

### 2. Stability: S9 — @State/@Observable audit (MEDIUM)
**File:** `Shared/Views/Dashboard/DashboardView.swift:5-6`

`TaskBoardService()` and `ScratchpadService()` created as `@State`. Confirm these use `@Observable` (correct pattern) vs `ObservableObject` (needs `@StateObject`). Low risk if already using `@Observable`.

### 3. Phase 0: Responsive widget content (MEDIUM)
**Files:** `Shared/Views/Components/WidgetShell.swift`, all widget views

Widget containers are user-resizable but content is hardcoded. Wrap `WidgetShell` in a `GeometryReader`, inject a `WidgetSizeClass` environment value (`.compact`/`.regular`/`.expanded`), and have each widget adapt font sizes and item counts accordingly.

See `docs/PLAN-calendar-todo-intelligence.md` § Phase 0 for full spec.

### 4. Minor stability (LOW — fix opportunistically)
| # | Where | Issue |
|---|-------|-------|
| S14 | `pi-kiosk/index.html` | localStorage quota not handled → silent data loss on `setItem()` |
| S15 | `pi-kiosk/index.html` | 2s polling race between settings.html writes and index.html reads |
| S16 | `Shared/Views/Dashboard/TerminalWidget.swift` | URLSession request not cancellable on view dismiss |
| S17 | `Shared/Services/WebSocketSession.swift` | UserDefaults unsafe casting, no type validation |
| S18 | `pi-kiosk/index.html` | fetch() calls with `.catch(()=>{})` silently swallow errors |

### 5. Future (don't build yet)
- Apple Mail integration for email context in briefings
- Back-to-back meeting brief bundling UI
- Voice input: ROADOM mic → Whisper → bridge WebSocket

---

## Infrastructure you need to know

### Pi (pihub.local / Tailscale: 100.120.26.124)
- Runs the kiosk web server on `:8430` and Claude bridge on `:8420`
- Deploy kiosk changes: `cd pi-kiosk && ./deploy.sh` (rsync + systemctl restart)
- **Never** edit files directly on the Pi — always edit locally and deploy

### Build & deploy iOS
```bash
xcodebuild -project alfredo.xcodeproj -scheme alfredo-iOS \
  -destination 'id=00008150-00027C183644401C' build

xcrun devicectl device install app \
  --device 00008150-00027C183644401C \
  ~/Library/Developer/Xcode/DerivedData/alfredo-bsnsupimkylzxhfsgrhgetcenjaf/Build/Products/Debug-iphoneos/alfredo.app
```

### Versioning convention
- Bump version in `alfredo.xcodeproj` + `pi-kiosk/index.html` (search `v0.4`)
- Tag commits: `git tag v0.X.Y && git push --tags`
- Separate tags for kiosk-only changes: `v0.X.Y-kiosk`

---

## Coordination rules (Claude + Codex working together)

1. **Always pull before starting work** — `git pull --ff-only`
2. **Small, atomic commits** — one logical change per commit, clear message
3. **Never force push to main**
4. **Don't touch the Pi directly** — all changes go through deploy.sh
5. **Check the plan doc first** — `docs/PLAN-calendar-todo-intelligence.md` is the source of truth for what's in scope
6. **The `docs/HANDOFF.md` file** (this file) should be updated when significant work completes or the plan changes
7. **Commit messages format:** `[surface] short description (vX.Y.Z)` — e.g. `[iOS] Fix WebSocket race in cleanup (v0.48.1)`

---

## Key files map

```
Shared/
  Models/          — Widget, Project, Layout models
  Services/        — WeatherService, ProjectService, MeetingPrepService,
                     BriefingScheduler, WebSocketSession, TaskBoardService
  Views/
    Dashboard/     — DashboardView, all widget views
    Components/    — WidgetShell, StatusDotsView, AlfredoInputBar
    Sheets/        — EventBriefingSheet, TaskBriefingSheet, ProjectDetailSheet

iOS/
  iOSTopChrome.swift
  Info.plist       — NSLocalNetworkUsageDescription + NSBonjourServices required

pi-kiosk/
  index.html       — main kiosk (1024×600)
  editor.html      — layout editor (settings page)
  serve.py         — Python HTTP server + proxy endpoints
  deploy.sh        — rsync + restart script

alfredo/           — Claude Code OS (task board, skills, memory)
docs/              — PLAN-calendar-todo-intelligence.md (main plan)
                     HANDOFF.md (this file)
```
