# alfredo — Cowork Context

Read this file at the start of every Cowork session. It tells you what this project is, where things stand, how Todd works, and how to delegate to Claude Code.

---

## What is alfredo?

Personal productivity dashboard built by Todd. Two surfaces, one purpose: give an ADHD brain a low-friction command centre.

**1. iOS + macOS Swift app** — infinite canvas with draggable/resizable widgets (tasks, habits, calendar, clock, terminal, scratchpad, goals, stats). Dark terminal aesthetic: JetBrains Mono, `#080E18` background, `#61AFEF` ice-blue accent, ASCII borders. No gradients, no illustrations, no shame UI. The terminal look is an ADHD accommodation, not decoration.

**2. Pi kiosk** — the same dashboard as a fullscreen Chromium web app on a Raspberry Pi with a 7" ROADOM touchscreen, always-on beside the desk. Talks to Claude Code via a bridge service on the Pi.

**The relationship:** The app is the visual layer. Claude Code manages the markdown files (tasks, habits, goals, scratchpad) through daily rituals. The user never edits files directly.

---

## How Todd works with Claude

- **Cowork = command centre.** Todd uses Cowork to think out loud, make decisions, direct work, and review what's been done.
- **Claude Code = execution engine.** Code writes Swift, deploys to the Pi, edits files, runs builds. Todd delegates implementation to Code from here.
- **Delegating to Code:** When a task needs implementation, tell Todd what to say to Claude Code (or draft the prompt directly). Format: paste into a Claude Code session running from `~/Projects/project alfredo/`.
- **Context lives in files.** The task board, memory, and scratchpad are the source of truth. Read them before making recommendations.

---

## Project location

```
~/Projects/project alfredo/       — Mac repo root
  CLAUDE.md                        — full project instructions (for Code)
  COWORK.md                        — this file (for Cowork)
  alfredo/                         — Claude OS (task board, memory, commands)
    Task Board.md                  — current tasks
    Scratchpad.md                  — quick capture
    .claude/memory.md              — active context, open threads
  docs/                            — design brief, context, Replit briefing
  assets/                          — icon SVGs
  alfredo.xcodeproj/               — Xcode project (iOS + macOS)
  Shared/ iOS/ macOS/              — Swift source
  pi-kiosk/                        — Pi web dashboard source
  pi-setup/                        — Pi systemd services + setup scripts
```

**Pi:** `todd@pihub.local` (Tailscale: `100.120.26.124`)
**Dashboard:** `http://pihub.local:8430/`
**Settings:** `http://pihub.local:8430/settings.html`

---

## Current build state (as of 2026-04-11)

**iOS + macOS app -- done:**
- Infinite canvas on both platforms -- single-finger pan + momentum, pinch-to-zoom 0.5x-2.0x
- Long-press enters edit mode + haptic feedback
- All widgets on `DashboardView` (tab layout removed)
- Bottom sheets for settings/widgets on iOS
- Terminal widget (`CLAUDE.TTY`) -- HTTP bridge to Claude Code on Pi
- Hamburger menu top-left, minimap auto-hides after 2s
- Terminal-style app icon
- Context-aware layout with weather timeline, ALFREDO.TTY, and flow layout (v0.48.0)
- Weekend calendar handling and weather cleanup (v0.49.0)
- Crash risk and stability fixes (v0.47.1)

**Pi kiosk -- done:**
- Fullscreen Chromium kiosk on ROADOM 7" (1024x600)
- Widgets: CLOCK.SYS, TODAY.EXE, WORK.TODO, LIFE.TODO, CALENDAR.DAT, CLAUDE.TTY, STATS.DAT, SCRATCH.PAD
- Status bar: BRIDGE · WS · NET · ICLOUD · TAILSCALE · SYNC · NEARBY
- Settings page with drag-and-drop layout editor, task/scratch editing, presence detection, live preview
- Triple-tap clock to exit kiosk; A-/A+ font size; layout presets: DEFAULT / FOCUS / TERMINAL
- Presence detection: pings `todds-MacBook-Pro.local` every 15s, screen dims after 10 min away
- Weather timeline with sun/moon dome arc (v0.48.0)
- Context-aware mode system (v0.47.0)

**Agent infrastructure -- done:**
- Codex agent system prompt for Alfredo Chief of Staff
- HANDOFF.md for peer agent coordination

---

## What's next (priority order)

1. **Voice input** — ROADOM USB mic → Whisper STT → bridge WebSocket `ws://localhost:8421/ws` → Claude response
2. **Real data sync** — pull tasks/habits/goals from iCloud markdown files into the kiosk (Pi can't read iCloud directly; need Mac to push via bridge or a shared endpoint)
3. **Philips Hue** — local REST API, needs bridge IP + token. Wire to voice commands. Light color tied to bridge status (green=idle, amber=thinking, red=error)
4. **GitHub sync** — repo setup, then Pi auto-pull via cron `git pull` + rsync after push
5. **Boot screen** — ASCII boot sequence on kiosk load (like `BootScreen.swift`)

---

## Key tech decisions (don't re-litigate these)

- **SwiftUI only** — no UIKit
- **Markdown files are the data layer** — no Core Data, no SQLite
- **iCloud Documents** for sync — container `iCloud.com.projectalfredo.app`
- **`@Observable`** state management
- **Terminal aesthetic is intentional** — it's an ADHD accommodation. No gradients, no illustrations, no high-saturation colours outside the accent system. Never add animations slower than 0.3s.
- **No shame UI** — tasks carry forward, overdue is never labelled as such, incomplete ≠ failure

---

## Design system quick reference

| Token | Value |
|-------|-------|
| Background | `#080E18` |
| Text primary | `#ABB2BF` |
| Text emphasis | `#E8EAED` |
| Text secondary | `#5C6370` |
| Accent (ice, default) | `#61AFEF` |
| Success | `#98C379` |
| Warning | `#E5C07B` |
| Danger | `#E06C75` |
| Font | JetBrains Mono |
| Border chars (default) | `╭─╮ │ ╰─╯` (round) |

Accent has four options: Ice / Coral / Amber / Green. User-selectable. Use opacity variants, never raw accent at full opacity everywhere.

---

## Deploy cheatsheet

```bash
# Deploy kiosk changes (Mac → Pi)
cd ~/Projects/project\ alfredo
rsync -av pi-kiosk/ pihub.local:~/alfredo-kiosk/
ssh pihub.local 'sudo systemctl restart alfredo-kiosk-web'

# Build + install iOS to iPhone
xcodebuild -project alfredo.xcodeproj -scheme alfredo-iOS \
  -destination 'id=00008150-00027C183644401C' build
xcrun devicectl device install app \
  --device 00008150-00027C183644401C \
  ~/Library/Developer/Xcode/DerivedData/alfredo-bsnsupimkylzxhfsgrhgetcenjaf/Build/Products/Debug-iphoneos/alfredo.app

# Build + launch macOS
xcodebuild -project alfredo.xcodeproj -scheme alfredo-macOS build
open ~/Library/Developer/Xcode/DerivedData/alfredo-bsnsupimkylzxhfsgrhgetcenjaf/Build/Products/Debug/alfredo.app

# Pi SSH shortcuts
ssh pihub.local 'sudo systemctl restart alfredo-bridge'
ssh pihub.local 'journalctl -u alfredo-bridge -f'
ssh pihub.local 'pkill -f chromium'   # drop to Pi desktop
```

---

## Files to read for current context

Before making task or project recommendations, read these:

1. `alfredo/Task Board.md` — what's active, soon, waiting
2. `alfredo/.claude/memory.md` — open threads, recent decisions, people context
3. `alfredo/Scratchpad.md` — anything captured mid-session that hasn't been processed

---

## How to keep this file current

Update the "Current build state" and "What's next" sections when major features ship or priorities shift. Everything else is stable. The detailed design spec lives in `docs/DESIGN-BRIEF.md` — don't duplicate it here.
