# alfredo — project context for new sessions

Paste this into a new agent session if you need a quick restart on the Alfredo project.

---

## What is alfredo?

Alfredo is Todd's personal productivity dashboard and ADHD operating system.

It runs across three connected surfaces:

1. **iOS app** — SwiftUI infinite canvas for capture, briefings, and mobile access
2. **macOS app** — the main desktop control surface, same shared SwiftUI codebase
3. **Pi kiosk** — fullscreen web dashboard on a Raspberry Pi with a ROADOM touchscreen and mic

The visual language is intentionally terminal-like: JetBrains Mono, dark background, ice-blue accent, ASCII borders, restrained motion, and no shame-driven task framing.

## Repo

- **GitHub**: `git@github.com:techops-rules/project-alfredo.git`
- **Mac project**: `~/Projects/project alfredo/`
- **Pi**: `todd@pihub.local` (Tailscale: `100.120.26.124`)

## Tech stack

| Layer | Tech |
|-------|------|
| iOS/macOS app | Swift, SwiftUI, infinite canvas, iCloud sync |
| Pi OS | Debian 13, Wayland (`labwc`), aarch64 |
| Pi kiosk | HTML/CSS/JS, Chromium kiosk mode |
| Pi bridge/services | Python systemd services |
| Data layer | markdown files in iCloud container / fallback documents path |

## Pi services

| Service | Purpose |
|---------|---------|
| `alfredo-bridge.service` | Claude/Codex bridge |
| `alfredo-kiosk-web.service` | kiosk web server on `:8430` |
| `alfredo-watchdog.timer` | health checks |
| `alfredo-wake.service` | wake listener / voice entry point (in progress) |

## Current product state

### Shipped / established

- SwiftUI infinite canvas on iOS and macOS
- draggable/resizable widgets
- calendar and task briefing flows
- terminal widget bridging to the Pi
- kiosk dashboard with mode-aware UI and layout tooling
- weather timeline and terminal-style system chrome

### In progress right now

- voice input path on the kiosk, including wake listener, kiosk voice UI, and native voice event polling
- Alfredo/Codex agent integration through the terminal and voice pipeline

### Approved roadmap after the current voice batch

- `v0.49.x`: smoothness first
  - stability fixes
  - responsive widget content
  - iPhone gesture cohesion
  - clearer sync/status affordances
  - safer kiosk settings/error handling
- `v0.50.x`: sync/helpfulness/ops
  - native-to-kiosk state sync
  - shared kiosk snapshot endpoints
  - stronger `What Next` / quick capture surfaces
  - deploy automation cleanup
  - kiosk boot polish

## Current priorities

1. **Voice input to Codex agent**
2. **Real native-to-kiosk sync**
3. **Cross-surface UX cleanup**
4. **Deploy and boot polish**
5. **Hue / later integrations**

## Key files

```
~/Projects/project alfredo/
├── alfredo.xcodeproj
├── Shared/
│   ├── App/
│   ├── Models/
│   ├── Services/
│   └── Views/
├── iOS/
├── macOS/
├── pi-kiosk/
│   ├── index.html
│   ├── settings.html
│   └── serve.py
├── pi-setup/
├── alfredo/
│   ├── Task Board.md
│   ├── Scratchpad.md
│   └── .claude/memory.md
├── docs/
│   ├── HANDOFF.md
│   ├── PLAN-calendar-todo-intelligence.md
│   └── CODEX-AGENT-ALFREDO.md
└── COWORK.md
```

## Working rules

- Check `git status` before editing when parallel work may be active.
- Read `docs/HANDOFF.md` and `alfredo/.claude/memory.md` before picking up implementation.
- Keep `docs/HANDOFF.md` and `alfredo/.claude/memory.md` updated after meaningful work batches.
- Do not assume older summaries are current if the repo state says otherwise.

## Useful URLs

- Dashboard: `http://pihub.local:8430/`
- Settings: `http://pihub.local:8430/settings.html`

## Useful tasks to read first

1. `alfredo/Task Board.md`
2. `alfredo/.claude/memory.md`
3. `alfredo/Scratchpad.md`
4. `docs/HANDOFF.md`
