# Alfredo UI Briefing — Widget Layout & Behavior

> For: Codex, Claude, or any agent working on interface improvements
> Last updated: 2026-04-11
> Surfaces: Pi kiosk (HTML/JS), iOS (SwiftUI), macOS (SwiftUI)

---

## Design Language

- Dark terminal aesthetic: `#1e1e2e` backgrounds, JetBrains Mono, restrained motion
- Accent: `#61afef` (blue), urgency: `#e06c75` (red), done: `#98c379` (green)
- No shame-driven task framing — neutral, clear status states
- ADHD-optimized: reduce noise, surface what matters now, hide the rest

---

## Three Surfaces

| Surface | Tech | Screen | Layout System |
|---------|------|--------|---------------|
| **Pi kiosk** | HTML/JS/CSS | 1024×600 ROADOM 7" | Mode-based absolute positioning (px) |
| **iOS** | SwiftUI | iPhone (375pt wide) | Context-aware flow layout (2 vertical screens) |
| **macOS** | SwiftUI | Free canvas | Persistent drag/resize, 20px grid snap |

---

## Pi Kiosk Widgets

### Widget Inventory

| ID | Title | Content | Data Source |
|----|-------|---------|-------------|
| `w-clock` | — | Time + date, colon blink | JS timer (0.53s) |
| `w-weather` | WEATHER | Sun/moon dome, hourly temps, conditions | Open-Meteo API (47.61°N, 122.33°W) |
| `w-hotlist` | HOTLIST | Urgent tasks + imminent events | localStorage |
| `w-work` | WORK.TODO | Work task list with done toggles | localStorage |
| `w-life` | LIFE.TODO | Personal task list | localStorage |
| `w-cal` | CALENDAR | Upcoming events, past auto-fade | localStorage |
| `w-today` | TODAY | Daily stats bar (done/total/hours/events) | localStorage |
| `w-scratch` | SCRATCH.PAD | Free-form notes | localStorage |
| `w-tty` | ALFREDO.TTY | Terminal / system status | Static placeholder |
| `w-stats` | STATS | Metrics | Static placeholder |
| `w-meeting` | MEETING | Active meeting info (immersive) | localStorage |

### Mode System (Auto-Switching)

| Mode | When | Key Behavior |
|------|------|-------------|
| **work** | Weekdays 6am–10pm | All task lists visible, calendar prominent |
| **meeting** | During active calendar event | Meeting widget goes immersive (992×410px), hides most others |
| **night** | 10pm–6am | Clock centered large, task lists compact (tap to expand), no calendar |
| **weekend** | Sat/Sun 6am–10pm | Life tasks promoted, scratch pad visible, work tasks hidden |
| **focus** | During deep work block | Work tasks go full-width immersive, everything else hidden |

Each mode defines pixel positions for every widget. Font size variants (`work-md`, `work-lg`) adjust positions when user scales text.

### Layout Details (Work Mode — Default)

```
┌─────────────────────────────────────────────────────────┐
│ CLOCK(190×140)  HOTLIST(300×165)  WEATHER(480×165)      │
│                                                          │
│ WORK.TODO(494×165)              LIFE.TODO(486×165)      │
│                                                          │
│ CALENDAR(494×195)               TODAY(195×195)          │
└─────────────────────────────────────────────────────────┘
Canvas: 1024×572 (after 28px status bar)
```

### Kiosk Interactions

- **Task circle tap** → toggle done
- **Blank dot at list bottom** → add new item (modal)
- **`+ add note...`** in scratch pad → add note
- **Widget header tap** → collapse/expand (compact class)
- **Triple-tap clock** → exit kiosk to desktop
- **A−/A+** buttons → font size scale
- **Mute button** (upper-right) → double-tap to toggle mic
- **Mic button** → push-to-talk voice activation
- **Status bar dots** → BRIDGE · WS · NET · ICLOUD · TAILSCALE · SYNC · NEARBY · MIC

### Voice UI Overlay

- **Voice toast**: fixed overlay, slides in from top on wake events
- **Voice bar**: 3px top bar — yellow pulse (listening), blue scan (thinking)
- **States**: idle → wake → listening → thinking → reply → dismissed

---

## iOS Widgets

### Widget Inventory

| Widget | SwiftUI View | Content |
|--------|-------------|---------|
| Clock | ClockWidget | Time + date |
| Weather | WeatherWidget | Sun/moon dome, hourly, conditions |
| Today Bar | TodayBarWidget | Stats row (done/total/hours/events) |
| Work Tasks | TaskListWidget(.work) | Task list with done toggles |
| Life Tasks | TaskListWidget(.life) | Personal tasks |
| Hotlist | HotlistWidget | Urgent tasks + imminent events |
| Calendar | CalendarWidget | Event list, past auto-clear |
| Habits | HabitWidget | Grid of circles, tap to mark done |
| Goals | GoalsWidget | Progress bar rows |
| Projects | ProjectsWidget | Project list with status |
| Scratchpad | ScratchpadWidget | Notes list |
| Terminal | TerminalWidget | ALFREDO.TTY — Claude Code bridge |
| Stats | StatsWidget | Metrics grid |
| Deferred Tasks | TaskListWidget(.deferred) | Deferred items |
| Waiting Tasks | TaskListWidget(.waiting) | Waiting-on items |
| Long-term Tasks | TaskListWidget(.longTerm) | Someday/maybe |
| Fun Fact | FunFactWidget | Random quote |

### Flow Layout (Context-Aware)

iOS computes layout dynamically — no saved positions. Two horizontal "screens" (swipeable):

**Screen 1** (always visible):
- Weather (full width, 130px tall) — always first
- Context-dependent: Hotlist → Calendar → primary task list

**Screen 2** (scroll right):
- Secondary task list, habits, projects, goals
- 2-column grid for deferred/waiting/long-term/stats
- Fun fact at bottom

**Context Rules:**
| Context | Primary List | Secondary List | Notes |
|---------|-------------|----------------|-------|
| Work (weekday day) | Work Tasks | Life Tasks | Calendar prominent |
| Night (10pm–6am) | Hotlist only | — | Minimal screen 1 |
| Weekend | Life Tasks | Work Tasks | Scratch pad visible |
| Personal | Work Tasks | Life Tasks | Default fallback |

### iOS Interactions

- **Task circle** → toggle done (blue dot → checkmark)
- **Task text** → TaskBriefingSheet (detail view with context)
- **Calendar event** → MeetingBriefingSheet (prep context with confidence scores)
- **Long-press task** → focus mode (fullscreen timer)
- **Long-press canvas** (>0.5s) → edit mode + haptic → drag/resize widgets
- **Pinch** → zoom 0.5x–2.0x with momentum spring
- **Single-finger pan** → scroll canvas with momentum

### Widget Sizing (WidgetContentMetrics)

Widgets adapt content to container size via `WidgetSizeClass`:

| Property | Compact (<260w) | Regular | Expanded (>430w) |
|----------|--------|---------|----------|
| List item limit | 3 | 5 | 8 |
| Secondary limit | 2 | 4 | 6 |
| Hour window | 5h | 7h | 11h |
| Grid columns | 2 | 3 | 3 |
| Body font | fs−1 | fs | fs |
| Content padding | 8px | 12px | 14px |

Compact widgets show "+N more hidden at this size" truncation message.

---

## macOS Widgets

Same widget set as iOS. Key differences:

- **Free-form canvas** (2800×1200 world size) — always draggable
- **Positions persist** to iCloud (debounced 300ms save)
- **20px grid snap** (8px threshold)
- **Min widget size**: 200×100
- **No context-aware switching** — user arranges manually
- **Scroll wheel** → pan canvas (no pinch zoom)

### Default macOS Layout

```
┌──────────────────────────────────────────────────────────────────┐
│ CLOCK    TODAY BAR              WEATHER        │ PROJECTS        │
│ (340×110)(840×110)              (500×200)      │ (500×320)       │
│                                                │                 │
│ WORK     LIFE      HABITS                      │ GOALS           │
│ (360×340)(360×340)  (440×340)                  │ (500×260)       │
│                                                │                 │
│ CALENDAR           HOTLIST                     │ SCRATCHPAD      │
│ (560×270)          (620×270)                   │ (420×600)       │
│                                                │                 │
│ STATS              TERMINAL    LONG-TERM       │ DEFERRED        │
│ (700×280)          (460×280)   (500×200)       │ WAITING         │
│                                                                  │
│ FUN FACT                                                         │
└──────────────────────────────────────────────────────────────────┘
```

---

## Data Architecture

### Data Sources

| Data | Service | Storage | Sync |
|------|---------|---------|------|
| Tasks | TaskBoardService | In-memory + iCloud files | Read from markdown files |
| Calendar | CalendarService | EventKit | System calendar API |
| Weather | WeatherService | In-memory cache | Open-Meteo API (no key) |
| Habits | Local @State | In-memory | None (resets on launch) |
| Goals | Local @State | In-memory | None |
| Scratchpad | ScratchpadService | In-memory | None |
| Terminal | HTTP to Pi :8420 | None | Per-request |
| Voice events | VoiceEventService | In-memory | Polls Pi :8430 every 2s |

### Cross-Surface Sync Status

| Data | iOS ↔ macOS | Native ↔ Pi |
|------|-------------|-------------|
| Tasks | iCloud (via markdown) | Not synced (Pi uses localStorage) |
| Calendar | Both read EventKit | Pi has no calendar data |
| Weather | Both call Open-Meteo | Both call Open-Meteo independently |
| Scratchpad | Not synced | Not synced |
| Layout | iOS ignores saved; macOS persists | Independent systems |

---

## Known Issues & Improvement Opportunities

### High Impact

1. **Pi kiosk tasks are siloed** — stored in browser localStorage only. No sync with iOS/macOS TaskBoardService. This is the biggest gap.

2. **Pi has no live calendar data** — events are localStorage stubs. Phase 4 planned but not started.

3. **Terminal widget is decorative on Pi** — shows static placeholder. Could show recent voice interactions, system status, or bridge health.

4. **Habits/goals don't persist** — iOS/macOS store in @State (lost on app restart). Need a persistence layer.

5. **Weather location hardcoded** — Pi: 47.61°N, 122.33°W (Seattle). No UI to change.

### Medium Impact

6. **iOS context-aware layout has no manual override** — user can't force a mode (e.g., "focus mode" on demand).

7. **macOS zoom level resets on launch** — `canvasScale` not persisted.

8. **Font size variants incomplete on Pi** — only work-md and work-lg defined. Extreme sizes may collide.

9. **Zone labels inconsistent** — Pi shows them visually, iOS/macOS compute but don't render.

10. **Clock timer mismatch** — Pi uses 0.53s, iOS uses 1.0s. Minor but divergent.

### Low Impact / Polish

11. **No loading states** — widgets show empty or stale data without indication.

12. **No error states** — if Open-Meteo or Pi bridge is down, widgets silently fail.

13. **FunFact has no API** — static quotes only.

14. **Status bar MIC dot on Pi** — exists but not wired to actual mic status from wake service.

15. **Compact mode tap-to-expand (night)** — works but has no visual affordance (just shows ▸ arrow).

---

## Voice System

### Architecture

```
USB Mic → alfredo-wake.service (Porcupine + WebRTC VAD)
  ↓ wake detected or push-to-talk
  ↓ Piper TTS ack → record command → POST to Codex bridge (:8420)
  ↓ Codex reply → Piper TTS speak → POST voice event to serve.py
  ↓
serve.py (:8430) holds event queue
  ↓ polled by:
  ├── pi-kiosk/index.html (voice toast + bar)
  ├── iOS VoiceEventService → TerminalWidget
  └── macOS VoiceEventService → TerminalWidget
```

### Persona

Personality profile at `~/alfredo-kiosk/persona.md` — loaded per Codex request, no restart needed.

Current persona: **Monday-inspired** — sardonic, competent, dry wit, warm underneath the mockery. "The competent snark machine in the passenger seat saying, 'That was a terrible turn. Here's how to fix it.'"

Key rules:
- Humor is garnish, not the meal — answer first, joke second
- 1–2 sentences max for voice (TTS)
- No emoji, no fake enthusiasm, no "Happy to help!"
- Tease like a friend, not a superior

### Voice Endpoints (serve.py)

| Endpoint | Method | Purpose |
|----------|--------|---------|
| `/proxy/voice-event` | POST | Wake listener posts events |
| `/proxy/voice-event?since=X` | GET | Clients poll events + mute state |
| `/proxy/voice-mute` | POST/GET | Toggle/check mute |
| `/proxy/voice-activate` | POST/GET | Push-to-talk trigger/poll |

---

## File Map

### Pi Kiosk
| File | What |
|------|------|
| `pi-kiosk/index.html` | Dashboard UI — all widgets, modes, voice overlay, interactions |
| `pi-kiosk/settings.html` | Settings/layout editor (Mac-accessible) |
| `pi-kiosk/serve.py` | HTTP server — proxies, voice events, mute, push-to-talk |

### Pi Setup
| File | What |
|------|------|
| `pi-setup/alfredo-wake.py` | Voice assistant — Porcupine + Piper TTS + push-to-talk |
| `pi-setup/alfredo-wake.service` | systemd unit for wake listener |
| `pi-setup/persona.md` | Voice personality profile (Monday) |

### iOS/macOS Shared
| File | What |
|------|------|
| `Shared/Views/Dashboard/DashboardView.swift` | Main canvas — InfiniteCanvas + widget layout |
| `Shared/Views/Dashboard/WidgetShell.swift` | Widget wrapper — header, badge, metrics |
| `Shared/Views/Dashboard/WidgetLayoutManager.swift` | Drag/resize + persistence |
| `Shared/Views/Dashboard/*Widget.swift` | Individual widget views |
| `Shared/Services/VoiceEventService.swift` | Polls Pi for voice events |
| `Shared/Services/TaskBoardService.swift` | Task data management |
| `Shared/Services/CalendarService.swift` | EventKit integration |
| `Shared/Services/WeatherService.swift` | Open-Meteo weather API |
| `Shared/Models/WidgetContentMetrics.swift` | Size-class responsive metrics |

---

## Principles for Improvement

1. **Consistency across surfaces** — same data, same status, same interaction patterns where possible.
2. **Show what matters now** — time-awareness, urgency, context. Hide the rest.
3. **No shame, no nag** — progress indicators, not guilt. Neutral language.
4. **Terminal aesthetic** — dark, monospace, minimal. Motion only where it communicates state.
5. **ADHD-friendly** — reduce decision load, surface the next action, don't overwhelm.
6. **Voice-first on kiosk** — the Pi should feel ambient and responsive, not like a web page.
