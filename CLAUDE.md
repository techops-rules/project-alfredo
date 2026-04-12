# alfredo — Claude Code Root

This is the root of the alfredo project. The Xcode app and the Claude Code operational system both live here.

## Project layout

| What | Path |
|------|------|
| **Xcode project** (iOS + macOS) | `alfredo.xcodeproj` (schemes: alfredo-iOS, alfredo-macOS) |
| **Swift source** | `Shared/`, `iOS/`, `macOS/` |
| **App icon assets** | `Resources/Assets.xcassets/AppIcon.appiconset/` |
| **Claude Code OS** (task board, slash commands, memory) | `alfredo/` |
| **Pi kiosk web files** | `pi-kiosk/` |
| **Pi setup / systemd services** | `pi-setup/` |
| **Project docs** (design brief, context, Replit briefing) | `docs/` |
| **Design / icon source files** | `assets/` |

## Build & deploy

```bash
# Build + install to iPhone (device ID: 00008150-00027C183644401C)
xcodebuild -project alfredo.xcodeproj -scheme alfredo-iOS \
  -destination 'id=00008150-00027C183644401C' build

xcrun devicectl device install app \
  --device 00008150-00027C183644401C \
  ~/Library/Developer/Xcode/DerivedData/alfredo-bsnsupimkylzxhfsgrhgetcenjaf/Build/Products/Debug-iphoneos/alfredo.app

# Build + launch macOS
xcodebuild -project alfredo.xcodeproj -scheme alfredo-macOS build
open ~/Library/Developer/Xcode/DerivedData/alfredo-bsnsupimkylzxhfsgrhgetcenjaf/Build/Products/Debug/alfredo.app
```

## Current state (as of 2026-04-11)

- [x] iOS infinite canvas — tab layout removed, `DashboardView` on all platforms
- [x] Single-finger pan + momentum (spring-based, no Timer)
- [x] Pinch-to-zoom 0.5x–2.0x
- [x] Long-press → edit mode + haptic
- [x] Bottom sheets for settings/widgets on iOS
- [x] Terminal widget (`CLAUDE.TTY`) — HTTP bridge to Claude Code on Pi
- [x] Hamburger menu top-left, minimap auto-hides after 2s
- [x] Terminal-style app icon
- [x] Pi kiosk dashboard — 7" ROADOM screen (1024×600), Chromium kiosk mode
- [x] Pi settings page — drag-and-drop layout editor, task/scratch editing, presence detection
- [x] Calendar time-awareness — past events auto-clear, live events bold+glow, 25min pre-meeting pulse
- [x] Tappable calendar events → MeetingBriefingSheet with confidence-scored context sources
- [x] Tappable task text → TaskBriefingSheet (circle still toggles done, long-press = focus mode)
- [x] MeetingPrepService — gathers context from calendar notes, recurrence history, task board, memory files
- [x] BriefingScheduler — 8am daily brief compilation + 25min pre-meeting notifications
- [x] Briefings pre-load in background on app launch
- [x] macOS scroll wheel panning fixed (moved before .drawingGroup())
- [x] Terminal/scratchpad keyboard input fixed (NSTextField replaces RawInputView)
- [x] Pi kiosk security: auth on system control endpoints, XSS fixed, command injection fixed
- [x] Crash risk and stability fixes across iOS app (v0.47.1)
- [x] Context-aware mode system on Pi kiosk (v0.47.0)
- [x] Weather timeline with sun/moon dome arc on Pi kiosk (v0.48.0)
- [x] iOS canvas redesign with weather timeline, ALFREDO.TTY, and flow layout (v0.48.0)
- [x] iOS context-aware layout, weather cleanup, weekend calendar (v0.49.0)
- [x] Codex agent system prompt + HANDOFF.md for peer agent coordination
- [x] Voice assistant — Porcupine wake word + Piper neural TTS + push-to-talk
- [x] Voice persona system — Monday-inspired personality profile, editable at runtime
- [x] Voice event propagation — kiosk visual feedback, iOS/macOS VoiceEventService
- [x] Mute button + voice state UI on kiosk
- [x] Pi recovery system — recover-pi.sh, boot-splash.html, self-healing with escalation
- [x] Recovery partition — /boot/alfredo-recovery/ for autonomous rebuild
- [x] Self-heal timer — L1 targeted fix → L2 restart → L3 reboot → L4 rebuild
- [x] Boot splash — terminal-style service checklist + TTS quip on kiosk startup
- [ ] Apple Mail integration for email context in briefings
- [ ] Responsive widget sizing (Phase 0)
- [ ] Pi kiosk live calendar data (Phase 4)
- [ ] Back-to-back meeting brief bundling UI

## Active implementation plan

**Read `docs/PLAN-calendar-todo-intelligence.md` before starting any feature work.** It contains:
- Pre-work stability audit (S1-S13): security fixes, crash fixes, memory leaks
- Bug fixes: scroll wheel panning (BF-A), ~~TTY yellow icon (BF-B, DONE)~~
- Phase 0: Responsive widget content (WidgetSizeClass environment)
- Phases 1-5: Calendar/todo intelligence (time-aware display, tappable events, context briefings, Pi kiosk integration)

Execute in the order listed in the plan. Run stability fixes first.

## Terminal widget Pi setup

Widget POSTs to `http://{host}:8420/chat`. Configure in app settings or:
```swift
UserDefaults.standard.set("pihub.local", forKey: "terminal.piHost")
UserDefaults.standard.set(8420, forKey: "terminal.piPort")
```
Pi needs: `GET /health` → 200 OK, `POST /chat` `{"prompt":"..."}` → `{"response":"..."}`

**iOS Local Network Privacy:** Terminal widget requires `NSLocalNetworkUsageDescription` and `NSBonjourServices` in `iOS/Info.plist` to connect to `.local` hostnames. Both are configured; if adding new local network features, ensure Info.plist has these keys.

## Pi kiosk — ROADOM 7" screen

**Hardware:** ROADOM 7" 1024×600 IPS touchscreen, connected via HDMI-A-1 + USB to pihub.local. UPS battery backup. USB microphone for wake word detection.

**Files on Pi:** `~/alfredo-kiosk/`
| File | Purpose |
|------|---------|
| `index.html` | Main kiosk dashboard (served at `http://localhost:8430/`) |
| `settings.html` | Mac-accessible settings UI (`http://pihub.local:8430/settings.html`) |
| `serve.py` | Python HTTP server on `:8430` — proxies health/iCloud/tailscale/presence/voice |
| `presence.json` | Hosts to ping for presence detection (currently: `todds-MacBook-Pro.local`) |
| `persona.md` | Voice personality profile — loaded by wake listener per request |

**Services:**
| Service | Port | Purpose |
|---------|------|---------|
| `alfredo-kiosk-web.service` | 8430 | Kiosk web server (systemd, auto-restart) |
| `alfredo-bridge.service` | 8420 (HTTP), 8421 (WS) | Claude Code bridge |
| `alfredo-wake.service` | — | Voice assistant (Porcupine + Piper TTS + push-to-talk) |
| `alfredo-watchdog.timer` | — | Watchdog every 2 min |

**Kiosk management:**
```bash
# Reload kiosk page
ssh pihub.local 'WAYLAND_DISPLAY=wayland-0 XDG_RUNTIME_DIR=/run/user/1000 chromium --ozone-platform=wayland http://localhost:8430/ 2>/dev/null &'

# Restart kiosk web server
ssh pihub.local 'sudo systemctl restart alfredo-kiosk-web'

# Kill kiosk (drops to Pi desktop)
ssh pihub.local 'pkill -f chromium'

# Hard relaunch kiosk fullscreen
ssh pihub.local 'systemd-run --user --unit=alfredo-kiosk-launch WAYLAND_DISPLAY=wayland-0 XDG_RUNTIME_DIR=/run/user/1000 chromium --kiosk --ozone-platform=wayland --noerrdialogs --no-first-run --start-fullscreen http://localhost:8430/'
```

**Kiosk features:**
- Triple-tap the clock (top-left) → exit kiosk to Pi desktop
- `A−` / `A+` buttons bottom-left → font size (persists in localStorage)
- Layout presets bottom-right: DEFAULT / FOCUS / TERMINAL
- Tap blank dot at bottom of any task list → add item (modal, persists)
- Tap `+ add note...` in SCRATCH.PAD → add note

**Status bar dots (bottom):** BRIDGE · WS · NET · ICLOUD · TAILSCALE · SYNC (staleness: green <5m, yellow 5–30m, red >30m) · NEARBY (presence ping)

**Settings page** (`http://pihub.local:8430/settings.html`):
- APPEARANCE: font size slider, accent color, widget toggles
- LAYOUT EDITOR: drag-and-drop widget canvas, save named layouts, apply to kiosk live
- TASKS / SCRATCHPAD: edit content, syncs to kiosk every 2s via shared localStorage
- BRIDGE: health check, voice/mic TODO notes
- PRESENCE: configure hostnames to ping, test detection
- PREVIEW: scaled live iframe mirror of kiosk

**Presence detection:** Pi pings `todds-MacBook-Pro.local` every 15s. NEARBY dot yellow after 5 min away, screen dims after 10 min via `wlr-randr --output HDMI-A-1 --off`.

**Autostart:** `~/.config/labwc/autostart` launches Chromium kiosk on boot (wayland-0, ozone-platform=wayland).

**Voice assistant:** `alfredo-wake.service` — Porcupine wake word ("alfredo" or fallback "jarvis") + Piper neural TTS + push-to-talk via kiosk mic button.
- Wake word requires `PICOVOICE_ACCESS_KEY` env var (free at picovoice.ai); without it, runs push-to-talk only
- Custom keyword file: `~/alfredo-kiosk/alfredo_wake.ppn` (train at console.picovoice.ai)
- Piper model: `~/piper-voices/en_US-lessac-medium.onnx` (natural-sounding neural TTS)
- Persona profile: `~/alfredo-kiosk/persona.md` — loaded per request, editable without restart. Monday-inspired: sardonic, competent, dry wit, warm underneath.
- Voice events posted to serve.py, polled by kiosk/iOS/macOS for visual feedback
- Mute button on kiosk (upper-right) silences wake + TTS
- Push-to-talk: kiosk mic button → POST `/proxy/voice-activate` → wake listener polls

**Voice API endpoints (serve.py on :8430):**
| Endpoint | Method | Purpose |
|----------|--------|---------|
| `/proxy/voice-event` | POST | Wake listener posts events (wake/listening/reply/dismissed) |
| `/proxy/voice-event?since=X` | GET | Kiosk/app polls events + mute state |
| `/proxy/voice-mute` | POST/GET | Toggle/check mute |
| `/proxy/voice-activate` | POST/GET | Push-to-talk trigger/poll |

**Planned / TODO:**
- [ ] Picovoice access key for wake word activation
- [ ] Custom "alfredo" .ppn keyword training
- [ ] Philips Hue light control via bridge
- [ ] Real data sync — pull tasks/habits/goals from iCloud markdown files via Mac push or bridge endpoint

## Pi recovery & self-healing

**Recovery from Mac** (after imaging fresh Pi OS):
```bash
cd ~/Projects/project\ alfredo
bash pi-setup/recover-pi.sh          # full install over SSH
bash pi-setup/setup-recovery-partition.sh  # populate /boot/alfredo-recovery/
```

**Self-healing** (`alfredo-self-heal.timer` — every 5 min):
| Level | Trigger | Action |
|-------|---------|--------|
| L1 | Health check fails | Diagnose + fix specific component (restore file, restart service, rebuild venv, clean disk) |
| L2 | 6 targeted fixes fail | Kill all + restart services |
| L3 | 3 broad restarts fail | Reboot (up to 2x) |
| L4 | 2 reboots fail | Full rebuild from `/boot/alfredo-recovery/` |

**Issue tracking:** Unresolvable issues logged to `~/alfredo-kiosk/issues/` with `[heal-todo]` git tag. Find with: `ssh pihub.local 'cd ~/alfredo-kiosk && git log --grep=heal-todo'`

**Boot splash:** `boot-splash.html` — shown on kiosk startup, checks all services with colored status dots, speaks a quip when done, then redirects to main kiosk.

**Recovery partition files** (`/boot/alfredo-recovery/`):
| Dir | Contents |
|-----|----------|
| `kiosk/` | index.html, serve.py, settings.html, editor.html, boot-splash.html |
| `bridge/` | alfredo-bridge.py, watchdog.sh, self-heal.sh |
| `services/` | All .service and .timer files |
| `config/` | persona.md, calendar-feeds.json, presence.json |
| `recover-local.sh` | Local rebuild script (runs on Pi) |

**Update recovery files** after code changes: `bash pi-setup/setup-recovery-partition.sh`
