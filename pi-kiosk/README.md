# alfredo · pi kiosk

Web dashboard running on pihub.local, displayed on a ROADOM 7" 1024×600 touchscreen via Chromium kiosk mode.

## Files

| File | Purpose |
|------|---------|
| `index.html` | Main kiosk dashboard UI (voice toast, mute button, push-to-talk) |
| `settings.html` | Settings/layout editor — open from Mac at `http://pihub.local:8430/settings.html` |
| `serve.py` | Python HTTP server on :8430, proxies health/iCloud/tailscale/presence/voice |

## Voice assistant

The kiosk integrates with `alfredo-wake.service` for voice interaction:

- **Mute button** (upper-right): double-tap to toggle. Shows "MIC LIVE" or "MUTED"
- **Push-to-talk**: mic button sends POST to `/proxy/voice-activate`
- **Voice toast**: overlay shows wake ack, listening state, thinking state, and reply text
- **Voice bar**: 3px bar at top — yellow pulse when listening, blue scan when thinking
- **Persona**: `~/alfredo-kiosk/persona.md` — Monday-inspired personality, editable without restart

## Deploy to Pi

```bash
# From Mac project root, after pulling latest
rsync -av pi-kiosk/ pihub.local:~/alfredo-kiosk/
ssh pihub.local 'sudo systemctl restart alfredo-kiosk-web'
```

## Reload kiosk after deploy

```bash
ssh pihub.local 'curl -s -X POST http://localhost:8430/reload-kiosk'
```

## URLs

- Kiosk: `http://pihub.local:8430/`
- Settings: `http://pihub.local:8430/settings.html`
