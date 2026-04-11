# Alfredo Multi-Platform Troubleshoot Plan

## Phase 1: Fix Terminal ANSI Escape Codes (macOS)

**Problem:** CLAUDE.TTY shows raw ANSI codes like `[3C[38;5;24dm2.[1C[39mNo` instead of rendered text. The Pi bridge sends raw PTY output with `TERM=xterm-256color`, but there's zero ANSI parsing anywhere in the Swift stack.

**Solution:** Add an ANSI stripping utility and apply it when processing terminal output.

### Tasks:
1. **Create `ANSIParser.swift`** in `Shared/Services/` — a simple regex-based ANSI escape code stripper
   - Strip CSI sequences: `\x1B\[[0-9;]*[A-Za-z]` (colors, cursor movement, etc.)
   - Strip OSC sequences: `\x1B\].*?\x07` (title sets, etc.)
   - Strip simple escapes: `\x1B[()][AB012]` (character set selection)
   - Function: `static func strip(_ text: String) -> String`
   
2. **Apply stripping in TerminalWidget.swift** — in the `handleWSMessage` function (around line 257-268), strip ANSI from `.output()` text before appending to lines:
   ```swift
   case .output(let text):
       let clean = ANSIParser.strip(text)
       let outputLines = clean.components(separatedBy: "\n")
   ```

3. **Also strip in HTTP fallback** — around line 460-464 in `sendToRemoteHTTP`, strip ANSI from the reply before splitting into lines.

### Verification:
- Build macOS app
- Launch and check CLAUDE.TTY — should show clean text, no escape codes
- Test by typing a command in the terminal widget

---

## Phase 2: Pi Kiosk Service Cleanup

**Problem:** `systemctl --user is-active alfredo-kiosk-web` reports "inactive" because the systemd unit files were never installed on the Pi. Processes run via labwc autostart, which works but means systemd can't manage them.

**Current state:** Everything is actually running fine — serve.py on :8430, bridge on :8420/:8421, Chromium kiosk fullscreen. All healthy.

### Tasks:
1. **Verify kiosk is displaying correctly** — SSH and check Chromium is showing the dashboard (already confirmed running)
2. **Install systemd user units on Pi** (optional but recommended):
   - Read `pi-setup/alfredo-bridge.service` and `pi-setup/alfredo-kiosk-web.service` from local repo
   - Fix paths in service files (actual: `/home/todd/alfredo-bridge.py`, service file says `/home/todd/alfredo-bridge/alfredo-bridge.py`)
   - SCP corrected files to `pihub.local:~/.config/systemd/user/`
   - `systemctl --user daemon-reload && systemctl --user enable alfredo-kiosk-web alfredo-bridge`
   - Note: Don't start them now since processes already running via autostart
3. **Sync kiosk files** — diff local `pi-kiosk/` against what's on the Pi at `~/alfredo-kiosk/` to check for drift

### Verification:
- `systemctl --user list-unit-files | grep alfredo` shows both units
- `curl -s http://pihub.local:8430/` returns kiosk HTML
- `curl -s http://pihub.local:8420/health` returns OK

---

## Phase 3: iOS Build, Deploy & Verify

**Problem:** iOS builds succeed but need to verify it runs correctly on device.

**Current state:** iPhone 17 Pro connected (F33D57B8-45A9-52C3-8C3C-077F029F5C86), signing configured with team 8TCJDHTU2X, all privacy keys present.

### Tasks:
1. **Build for device:**
   ```bash
   xcodebuild -project alfredo.xcodeproj -scheme alfredo-iOS \
     -destination 'id=00008150-00027C183644401C' build
   ```
2. **Install on device:**
   ```bash
   xcrun devicectl device install app \
     --device 00008150-00027C183644401C \
     ~/Library/Developer/Xcode/DerivedData/alfredo-bsnsupimkylzxhfsgrhgetcenjaf/Build/Products/Debug-iphoneos/alfredo.app
   ```
3. **Verify app launches** — check for crashes in device logs
4. **Test key features:**
   - Canvas panning and pinch-to-zoom
   - Calendar widget showing events
   - Terminal widget connectivity (if Pi reachable from phone network)
   - Long-press edit mode + haptic

### Verification:
- App installs without signing errors
- App launches and shows boot screen → dashboard
- No crash logs in `xcrun devicectl device get-diagnostics`

---

## Phase 4: Final Verification

1. macOS: CLAUDE.TTY shows clean text (no ANSI codes)
2. Pi kiosk: All services running, kiosk displaying correctly
3. iOS: App running on device, core interactions working
4. All three platforms build cleanly
