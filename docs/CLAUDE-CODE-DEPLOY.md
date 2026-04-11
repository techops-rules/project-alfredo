# Claude Code Deploy Instructions: Alfredo Agent + Push Notifications

> Date: 2026-04-11
> From: Cowork session
> For: Claude Code (running on Mac or Pi)

## Context

Cowork just made the following changes to the repo at `~/Projects/project-alfredo`:

### Modified files (Cowork changes only -- other widget layout changes were pre-existing)
- `Shared/App/alfredoApp.swift` -- added AppDelegate for APNs device token registration
- `Shared/Services/BriefingScheduler.swift` -- registers for remote notifications after permission granted
- `Shared/Services/WebSocketSession.swift` -- added `agentMode` property, sends `mode` in WS init message
- `Shared/Views/Dashboard/TerminalWidget.swift` -- defaults to agent mode, title shows ALFREDO.TTY, added /agent and /raw commands
- `alfredo.entitlements` -- added `aps-environment` = `development`
- `iOS/Info.plist` -- added `UIBackgroundModes` with `remote-notification`
- `pi-setup/alfredo-bridge.py` -- v3: reads mode from init, loads agent system prompt, added /register-push endpoint

### New files
- `Shared/Services/PushTokenService.swift` -- sends APNs device token to Pi bridge
- `pi-setup/apns-send.py` -- standalone APNs push sender for the Pi
- `pi-setup/alfredo-wake.py` -- wake word listener (Whisper + WebRTC VAD)
- `pi-setup/alfredo-wake.service` -- systemd unit for wake listener
- `pi-kiosk/setup-voice.sh` -- installs voice deps on Pi
- `docs/COWORK-INSTRUCTIONS.md` -- full implementation spec

### Pre-existing uncommitted changes (from earlier widget layout work)
These were already in the working tree before Cowork touched anything:
- `Shared/Views/Dashboard/WidgetLayout.swift` (new, untracked)
- Various widget view files (CalendarWidget, HotlistWidget, etc.) -- responsive layout refactoring
- `Shared/Views/Components/WidgetShell.swift` -- WidgetMetrics environment
- `CLAUDE.md`, `COWORK.md` -- minor updates

---

## Step 1: Commit the changes

There are two logical commits here. The pre-existing widget layout work and the new agent/push work.

```bash
cd ~/Projects/project-alfredo
git pull --ff-only

# Commit 1: Widget layout refactoring (pre-existing work)
git add \
  Shared/Views/Dashboard/WidgetLayout.swift \
  Shared/Views/Components/WidgetShell.swift \
  Shared/Views/Components/TodoItemView.swift \
  Shared/Views/Dashboard/CalendarWidget.swift \
  Shared/Views/Dashboard/GoalsWidget.swift \
  Shared/Views/Dashboard/HabitWidget.swift \
  Shared/Views/Dashboard/HotlistWidget.swift \
  Shared/Views/Dashboard/ProjectsWidget.swift \
  Shared/Views/Dashboard/ScratchpadWidget.swift \
  Shared/Views/Dashboard/StatsWidget.swift \
  Shared/Views/Dashboard/TaskListWidget.swift \
  Shared/Views/Dashboard/TodayBarWidget.swift \
  CLAUDE.md COWORK.md

git commit -m "[iOS] Responsive widget layout with WidgetMetrics environment (v0.50.0)"

# Commit 2: Agent mode + push notifications
git add \
  Shared/App/alfredoApp.swift \
  Shared/Services/BriefingScheduler.swift \
  Shared/Services/WebSocketSession.swift \
  Shared/Services/PushTokenService.swift \
  Shared/Views/Dashboard/TerminalWidget.swift \
  alfredo.entitlements \
  iOS/Info.plist \
  pi-setup/alfredo-bridge.py \
  pi-setup/apns-send.py \
  pi-setup/alfredo-wake.py \
  pi-setup/alfredo-wake.service \
  pi-kiosk/setup-voice.sh \
  docs/COWORK-INSTRUCTIONS.md \
  docs/CLAUDE-CODE-DEPLOY.md

git commit -m "[all] Agent mode, APNs push registration, voice/wake service (v0.50.1)"
```

Review the diffs before committing. The widget layout changes were in-progress -- check `git diff` on those files to confirm they look right.

---

## Step 2: Build and deploy iOS app

```bash
cd ~/Projects/project-alfredo

xcodebuild -project alfredo.xcodeproj -scheme alfredo-iOS \
  -destination 'id=00008150-00027C183644401C' build

# If build succeeds:
xcrun devicectl device install app \
  --device 00008150-00027C183644401C \
  ~/Library/Developer/Xcode/DerivedData/alfredo-bsnsupimkylzxhfsgrhgetcenjaf/Build/Products/Debug-iphoneos/alfredo.app
```

**If the build fails** on push notification entitlements, it likely means the provisioning profile doesn't have Push Notifications enabled. Todd needs to:
1. Go to developer.apple.com > Certificates, Identifiers & Profiles
2. Find the app ID for com.todd.alfredo (or whatever the bundle ID is)
3. Enable "Push Notifications" capability
4. Regenerate the provisioning profile

---

## Step 3: Deploy bridge + agent prompt to Pi

```bash
cd ~/Projects/project-alfredo

# Copy updated bridge
scp pi-setup/alfredo-bridge.py pihub.local:~/alfredo-kiosk/

# Copy Codex agent system prompt
scp docs/CODEX-AGENT-ALFREDO.md pihub.local:~/alfredo-kiosk/agent-prompt.txt

# Restart bridge service
ssh pihub.local 'sudo systemctl restart alfredo-bridge'

# Verify
ssh pihub.local 'sudo systemctl status alfredo-bridge --no-pager'
curl -s http://pihub.local:8420/health | python3 -m json.tool
```

---

## Step 4: Voice setup on Pi (optional, do this after confirming agent mode works)

```bash
cd ~/Projects/project-alfredo

# Install deps
scp pi-kiosk/setup-voice.sh pihub.local:~/alfredo-kiosk/
ssh pihub.local 'bash ~/alfredo-kiosk/setup-voice.sh'

# Deploy wake service
scp pi-setup/alfredo-wake.py pi-setup/alfredo-wake.service pihub.local:~/alfredo-kiosk/
ssh pihub.local 'sudo cp ~/alfredo-kiosk/alfredo-wake.service /etc/systemd/system/'
ssh pihub.local 'sudo systemctl daemon-reload && sudo systemctl enable --now alfredo-wake'

# Verify
ssh pihub.local 'sudo systemctl status alfredo-wake --no-pager'
```

---

## Step 5: APNs key setup (requires Todd)

Todd needs to create an APNs .p8 key from the Apple Developer Console:
1. https://developer.apple.com/account/resources/authkeys/list
2. Create key, check "Apple Push Notifications service (APNs)"
3. Download the .p8 file, note the Key ID
4. Note Team ID from Account > Membership

Then:
```bash
# Copy key to Pi
scp ~/Downloads/AuthKey_XXXXXXXXXX.p8 pihub.local:~/alfredo-kiosk/

# Edit config on Pi
ssh pihub.local 'cat ~/alfredo-kiosk/apns-config.json'
# Update key_path, key_id, team_id with real values
```

---

## Verification checklist

- [ ] `git log --oneline -3` shows both new commits
- [ ] iOS app builds without errors
- [ ] App installs on iPhone (device 00008150-00027C183644401C)
- [ ] Open app, ALFREDO.TTY widget shows "agent mode // codex system prompt active"
- [ ] `/status` in terminal shows `agent: on (codex prompt)`
- [ ] Type "what's next?" and get a response in Alfredo voice
- [ ] `curl -s http://pihub.local:8420/health` returns OK
- [ ] Bridge logs show `Agent mode: loading system prompt` on WS connect
- [ ] (After APNs setup) Push notification arrives on iPhone
