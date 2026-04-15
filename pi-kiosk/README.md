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
- **Push-to-talk**: mic button now prefers a realtime WebRTC voice session; legacy `/proxy/voice-activate` remains as fallback infrastructure
- **Transcription**: recorded mic audio is transcribed locally with Whisper `tiny.en`
- **Agent handoff**: the transcript is sent to `alfredo-bridge` in `agent` mode so the Codex system prompt is applied
- **Voice toast**: overlay shows wake ack, listening state, thinking state, and reply text
- **Voice bar**: 3px bar at top — yellow pulse when listening, blue scan when thinking
- **Persona**: `~/alfredo-kiosk/persona.md` — Monday-inspired personality, editable without restart
- **Wake word fallback**: `alfredo-wake` now prefers Picovoice when `PICOVOICE_ACCESS_KEY` is set, otherwise falls back to `openWakeWord` with the built-in `hey jarvis` model; if neither path is available, it stays in push-to-talk mode

## Realtime voice

The kiosk now includes a kiosk-first realtime voice path:

- **Broker endpoint**: `POST /proxy/realtime/session` mints a short-lived OpenAI Realtime session secret
- **Transport**: browser WebRTC to the Realtime API with server-side secrets only
- **Tools**: `POST /proxy/realtime/tool` resolves calendar/task/memory queries and scoped actions
- **Actions**: create task, create follow-up, create reminder
- **Current requirement**: set `OPENAI_API_KEY` on the Pi before realtime voice can connect
- **Fallback**: if realtime setup fails, the wake service remains installed and healthy, but the kiosk button no longer auto-falls back to Whisper/TTS

## Direct Mode

Direct Mode is the first slice of Alfredo's explicit multi-turn assistant mode:

- Say a phrase like "talk to Alfredo" or "direct mode" to enter a live assistant session
- The kiosk posts a `session` voice event so kiosk/native surfaces show Direct Mode as active
- Follow-up turns stay in the same session until a stop phrase or idle timeout closes it
- Kiosk context snapshots now include current work/life tasks, scratchpad text, and calendar events
- Slice 1 is read-only: it can answer from context, but it does not create reminders, tasks, or travel plans yet

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
