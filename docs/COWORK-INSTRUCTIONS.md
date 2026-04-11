# Cowork Instructions: Alfredo Agent Deployment

> For: Claude (Cowork mode, with access to ~/Projects/project-alfredo)
> From: Claude Code (Pi)
> Date: 2026-04-11

---

## Overview

Three things need to happen to get the Codex agent (Alfredo) running end-to-end:

1. **CLAUDE.TTY defaults to `/ws/agent` mode** — the terminal widget starts in agent mode, sending messages through the bridge with the Codex system prompt baked in
2. **iOS push notification registration** — the app registers for APNs, sends its device token to the Pi
3. **Pi APNs endpoint** — the bridge can fire a push notification to the iPhone when the agent finishes responding

---

## Task 1: Default CLAUDE.TTY to Agent Mode

### What to change

**File:** `Shared/Views/Dashboard/TerminalWidget.swift`

The `TerminalSession` currently defaults to raw WebSocket mode. Add:

- A new `/agent` command that switches to agent mode
- A new `/raw` command that switches back to raw PTY mode  
- Default `useAgentMode = true` on init
- When in agent mode, the init message sent to the bridge includes `"mode": "agent"`

The bridge (Task 3 below) will read this flag and prepend the Codex system prompt when spawning claude.

### TerminalSession changes

1. Add `private var useAgentMode = true` property
2. In `attemptWebSocket()`, change the system message to reflect agent mode
3. In `connect()` on WebSocketSession, the init message should include `"mode": useAgentMode ? "agent" : "raw"`
4. Add `/agent` and `/raw` commands to `handleCommand()`
5. Update `/status` to show current mode
6. Update `/help` to list new commands
7. Change the widget title from `"CLAUDE.TTY"` to `"ALFREDO.TTY"` when in agent mode

### WebSocketSession changes

**File:** `Shared/Services/WebSocketSession.swift`

1. Add `var agentMode: Bool = true` property
2. Include `"mode": agentMode ? "agent" : "raw"` in the init JSON sent on connect

---

## Task 2: iOS Push Notification Registration

### What to change

**File:** `Shared/App/alfredoApp.swift`

SwiftUI apps can't directly use `UIApplicationDelegate` for push registration without an adapter. Add an `AppDelegate` class that handles push token registration.

```swift
#if os(iOS)
class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        print("[APNs] Device token: \(token)")
        // Send token to Pi bridge
        PushTokenService.shared.register(token: token)
    }
    
    func application(_ application: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("[APNs] Registration failed: \(error.localizedDescription)")
    }
}
#endif
```

Wire it in with `@UIApplicationDelegateAdaptor`:

```swift
#if os(iOS)
@UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
#endif
```

### New file: `Shared/Services/PushTokenService.swift`

Sends the device token to the Pi bridge so it can fire APNs later:

```swift
import Foundation

@Observable
final class PushTokenService {
    static let shared = PushTokenService()
    
    private(set) var deviceToken: String?
    private(set) var isRegistered = false
    
    private init() {}
    
    func register(token: String) {
        self.deviceToken = token
        sendTokenToBridge(token)
    }
    
    private func sendTokenToBridge(_ token: String) {
        let host = UserDefaults.standard.string(forKey: "terminal.piHost") ?? ""
        guard !host.isEmpty else { return }
        let port = UserDefaults.standard.object(forKey: "terminal.piPort") as? Int ?? 8420
        
        guard let url = URL(string: "http://\(host):\(port)/register-push") else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: [
            "device_token": token,
            "bundle_id": Bundle.main.bundleIdentifier ?? "com.todd.alfredo"
        ])
        
        URLSession.shared.dataTask(with: request) { [weak self] _, response, error in
            if let http = response as? HTTPURLResponse, http.statusCode == 200 {
                DispatchQueue.main.async { self?.isRegistered = true }
            }
        }.resume()
    }
}
```

### Request push permission

In `BriefingScheduler.swift`, update `requestNotificationPermission()`:

```swift
private func requestNotificationPermission() {
    let center = UNUserNotificationCenter.current()
    center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
        if granted {
            DispatchQueue.main.async {
                #if os(iOS)
                UIApplication.shared.registerForRemoteNotifications()
                #endif
            }
        }
    }
}
```

### Entitlements

**File:** `alfredo.entitlements`

Add the push notification entitlement:

```xml
<key>aps-environment</key>
<string>development</string>
```

### Info.plist

**File:** `iOS/Info.plist`

Add background modes for remote notifications:

```xml
<key>UIBackgroundModes</key>
<array>
    <string>remote-notification</string>
</array>
```

---

## Task 3: Pi Bridge — Agent Mode + APNs Endpoint

### What to change

**File:** `pi-setup/alfredo-bridge.py`

1. **Agent mode in WS handler:** When the init message includes `"mode": "agent"`, spawn claude with `--system-prompt` pointing to the Codex system prompt file on the Pi:

```python
if mode == "agent":
    system_prompt_path = os.path.expanduser("~/alfredo-kiosk/agent-prompt.txt")
    if os.path.exists(system_prompt_path):
        claude_cmd.extend(["--system-prompt", system_prompt_path])
```

2. **Deploy the system prompt:** The deploy script should copy `docs/CODEX-AGENT-ALFREDO.md` to `~/alfredo-kiosk/agent-prompt.txt` on the Pi (strip the markdown frontmatter, just the raw instructions).

3. **APNs push endpoint:** Add `POST /register-push` (stores device token) and `POST /send-push` (internal, fires a notification via APNs).

### APNs on the Pi

The Pi needs:
- An APNs `.p8` auth key file from Apple Developer Console
- The key ID, team ID, and bundle ID
- A small Python APNs client (use `httpx` with HTTP/2 or the `apns2` pip package)

Store config in `~/alfredo-kiosk/apns-config.json`:
```json
{
    "key_path": "/home/pi/alfredo-kiosk/AuthKey_XXXXXXXXXX.p8",
    "key_id": "XXXXXXXXXX",
    "team_id": "XXXXXXXXXX",
    "bundle_id": "com.todd.alfredo",
    "device_token": null
}
```

The bridge updates `device_token` when it receives `POST /register-push`.

---

## Task 4: APNs Key Setup (Manual — Todd must do this)

1. Go to https://developer.apple.com/account/resources/authkeys/list
2. Create a new key, check "Apple Push Notifications service (APNs)"
3. Download the `.p8` file (you only get one download)
4. Note the Key ID shown on the page
5. Note your Team ID (top right of the developer portal, or Account > Membership)
6. SCP the .p8 file to the Pi:
   ```bash
   scp ~/Downloads/AuthKey_XXXXXXXXXX.p8 pihub.local:~/alfredo-kiosk/
   ```
7. Update `~/alfredo-kiosk/apns-config.json` with the key ID and team ID

---

## Deployment Order

```bash
# 1. Build and deploy iOS app (from Mac)
cd ~/Projects/project-alfredo
git pull --ff-only
xcodebuild -project alfredo.xcodeproj -scheme alfredo-iOS \
  -destination 'id=00008150-00027C183644401C' build
xcrun devicectl device install app \
  --device 00008150-00027C183644401C \
  ~/Library/Developer/Xcode/DerivedData/alfredo-*/Build/Products/Debug-iphoneos/alfredo.app

# 2. Deploy bridge + kiosk to Pi
bash pi-kiosk/deploy.sh
scp pi-setup/alfredo-bridge.py pihub.local:~/alfredo-kiosk/
ssh pihub.local 'sudo systemctl restart alfredo-bridge'

# 3. Copy agent system prompt to Pi
scp docs/CODEX-AGENT-ALFREDO.md pihub.local:~/alfredo-kiosk/agent-prompt.txt

# 4. Configure APNs (after Todd provides .p8 key)
# See Task 4 above

# 5. Voice/wake word (optional, after mic setup)
# See setup-voice.sh and alfredo-wake.service
```

---

## What "done" looks like

1. Open alfredo on iPhone
2. ALFREDO.TTY shows "agent mode" in the status bar
3. Type "what's next?" and get a response in the Alfredo voice (direct, warm, ADHD-aware)
4. When the agent finishes responding, iPhone gets a push notification: "alfredo is ready"
5. The agent has access to the Codex system prompt rules (ADHD operating rules, daily routines, voice patterns)
