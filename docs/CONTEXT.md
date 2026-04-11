# alfredo — project context for new sessions

Paste this into Claude to resume work on the alfredo project.

---

## What is alfredo?

Personal productivity dashboard / command centre built by Todd. Two parts:

1. **iOS + macOS Swift app** — infinite canvas with draggable/resizable widgets (tasks, habits, calendar, clock, terminal, scratchpad, goals, stats). Dark terminal aesthetic (JetBrains Mono, `#080E18` bg, `#61AFEF` ice accent).
2. **Pi kiosk** — same dashboard running as a fullscreen web app on a Raspberry Pi with a 7" touchscreen, always-on beside the desk.

## Repo

- **GitHub**: [fill in once created]
- **Mac project**: `~/Projects/project alfredo/`
- **Pi**: `todd@pihub.local` (Tailscale: `100.120.26.124`)

## Tech stack

| Layer | Tech |
|-------|------|
| iOS/macOS app | Swift, SwiftUI, infinite canvas, iCloud sync |
| Pi OS | Debian 13 (trixie), Wayland (labwc), aarch64 |
| Pi kiosk | Chromium kiosk mode, JetBrains Mono, localStorage sync |
| Pi bridge | Python (`alfredo-bridge.py`) — HTTP :8420, WebSocket :8421 → spawns `claude` PTY |
| Pi kiosk server | Python (`serve.py`) — HTTP :8430, proxies health/iCloud/tailscale/presence |

## Pi services

| Service | Purpose |
|---------|---------|
| `alfredo-bridge.service` | Claude Code bridge (HTTP + WS) |
| `alfredo-kiosk-web.service` | Kiosk web server :8430 |
| `alfredo-watchdog.timer` | Health check every 2 min |

## Kiosk URLs

- **Dashboard**: `http://pihub.local:8430/`
- **Settings** (Mac browser): `http://pihub.local:8430/settings.html`

## Kiosk features built

- CLOCK.SYS, TODAY.EXE, WORK.TODO, LIFE.TODO, CALENDAR.DAT, CLAUDE.TTY, STATS.DAT, SCRATCH.PAD widgets
- Status bar: BRIDGE · WS · NET · ICLOUD · TAILSCALE · SYNC (staleness green→yellow→red) · NEARBY (presence ping)
- Triple-tap clock → exit kiosk to Pi desktop
- A− / A+ font size controls (bottom-left of status bar)
- Layout presets: DEFAULT / FOCUS / TERMINAL
- Tap blank dot → add task (modal, localStorage)
- Settings page: drag-and-drop layout editor, task/scratch editing, presence config, live preview iframe

## Key files

```
~/Projects/project alfredo/
├── alfredo.xcodeproj          # iOS + macOS (schemes: alfredo-iOS, alfredo-macOS)
├── Shared/                    # Swift source (shared)
│   ├── Views/Dashboard/       # DashboardView, widgets, InfiniteCanvas
│   ├── Theme/TerminalTheme.swift  # ThemeManager, colors, BorderChars
│   └── Models/                # Task, Habit, Goal, WidgetLayout, etc.
├── iOS/                       # iOS-specific
├── macOS/                     # macOS-specific
├── pi-kiosk/                  # Web dashboard for Pi screen
│   ├── index.html             # Main kiosk UI
│   ├── settings.html          # Mac-accessible settings/layout editor
│   └── serve.py               # HTTP server + proxies
├── CLAUDE.md                  # Full project instructions
└── DESIGN-BRIEF.md            # Design spec

# On Pi: ~/alfredo-kiosk/ (deployed from pi-kiosk/ via rsync)
```

## Deploy kiosk changes (Mac → Pi)

```bash
cd ~/Projects/project\ alfredo
rsync -av pi-kiosk/ pihub.local:~/alfredo-kiosk/
ssh pihub.local 'sudo systemctl restart alfredo-kiosk-web && curl -s -X POST http://localhost:8430/reload-kiosk'
```

## Useful SSH commands

```bash
# Relaunch kiosk fullscreen
ssh pihub.local 'systemd-run --user WAYLAND_DISPLAY=wayland-0 XDG_RUNTIME_DIR=/run/user/1000 chromium --kiosk --ozone-platform=wayland --no-first-run --start-fullscreen http://localhost:8430/'

# Kill kiosk (go to Pi desktop)
ssh pihub.local 'pkill -f chromium'

# Display off/on
ssh pihub.local 'WAYLAND_DISPLAY=wayland-0 XDG_RUNTIME_DIR=/run/user/1000 wlr-randr --output HDMI-A-1 --off'
ssh pihub.local 'WAYLAND_DISPLAY=wayland-0 XDG_RUNTIME_DIR=/run/user/1000 wlr-randr --output HDMI-A-1 --on'

# Bridge logs
ssh pihub.local 'journalctl -u alfredo-bridge -f'

# Restart bridge
ssh pihub.local 'sudo systemctl restart alfredo-bridge'
```

## Presence detection

Pi pings `todds-MacBook-Pro.local` every 15s. NEARBY dot:
- 🟢 Green = Mac reachable
- 🟡 Yellow = not seen >5 min  
- 🔴 Red = not seen >30 min, screen turns off after 10 min

Configure hosts at: Settings → PRESENCE, or `POST /proxy/presence-hosts {"hosts":["hostname.local"]}`

## TODO / next up

- [ ] **GitHub sync** — repo setup in progress (fill in URL when done)
- [ ] **Pi auto-pull** — cron `git pull` + rsync on Pi after push
- [ ] **Philips Hue** — local REST API, needs bridge IP + token (1x button press). Wire to voice commands
- [ ] **Voice input** — ROADOM USB mic → Whisper STT → bridge WebSocket ws://localhost:8421/ws → Claude response
- [ ] **Real data sync** — pull tasks/habits/goals from iCloud markdown files into kiosk (Pi can't read iCloud directly; need Mac to push via bridge or shared endpoint)
- [ ] **Boot screen** — replicate BootScreen.swift style ASCII boot sequence on kiosk load
- [ ] **Hue status** — light color tied to bridge status (green=idle, amber=thinking, red=error)

## App theme reference

```swift
background   = #080E18
textPrimary  = #ABB2BF
textSecondary= #5C6370
textEmphasis = #E8EAED
accent (ice) = #61AFEF
success      = #98C379
warning      = #E5C07B
danger       = #E06C75
font         = JetBrains Mono
borderChars  = ╭─╮│╰─╯ (round, default)
```

## iPhone device ID (for Xcode deploy)
`00008150-00027C183644401C`
