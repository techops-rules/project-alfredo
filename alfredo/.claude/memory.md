# Memory

## Now
- Claude is actively landing kiosk mic and voice-event plumbing for Alfredo/Codex agent work.
- Codex refreshed the shared repo notes from the live working tree on 2026-04-11 so future sessions start from current state instead of stale summaries.
- Codex started the first UI polish pass on 2026-04-12:
  - rebuilt iPhone top chrome
  - switched iPhone canvas world sizing to flow-derived bounds
  - disabled canvas panning during edit mode
  - added kiosk widget size classes and surfaced ALFREDO.TTY in work mode
  - turned the kiosk terminal into a live status/voice feed
  - validated native builds with no-signing macOS + iOS simulator builds
- Codex patched the remaining kiosk mic handoff gap on 2026-04-12:
  - `alfredo-wake.py` now transcribes recorded speech with local Whisper before calling the bridge
  - voice requests now hit `alfredo-bridge` `/chat` with `mode: "agent"`
  - kiosk/native voice events now show the actual spoken transcript instead of a placeholder
- Codex landed Direct Mode Slice 1 on 2026-04-12:
  - new `DirectModeSessionService`, `DirectModeContextService`, and `DirectModeSheet`
  - explicit "Talk to Alfredo" entry points on iOS/macOS
  - kiosk direct-session start/stop, timeout, history, and context snapshot plumbing
  - direct turns are read-only and use schedule/task/project/memory context
- Codex completed a follow-up deploy/recovery pass on 2026-04-12:
  - Pi services on `pihub.local` were synced and restarted successfully after restoring runtime-only files removed by an overly aggressive `rsync --delete`
  - future Pi deploys should preserve runtime-owned files in `~/alfredo-kiosk/` instead of treating that directory like a pure git mirror
  - iPhone boot splash now includes a short update banner so fresh app runs visibly show the Direct Mode rollout
- Codex implemented the kiosk realtime voice stack on 2026-04-13:
  - `serve.py` now brokers short-lived Realtime sessions and dispatches Alfredo context/action tools
  - `index.html` now opens a WebRTC voice session, handles tool calls, and updates kiosk task/waiting state immediately from action results
  - realtime actions currently persist into kiosk local state first, then sync back into `/proxy/direct-context`

## Open Threads
- Voice path: ROADOM mic / wake listener -> kiosk voice event queue -> kiosk overlay + native polling -> Alfredo/Codex agent handoff.
- Cross-surface UX plan is approved and waiting behind the current voice integration batch.
- Real native-to-kiosk sync is still a major follow-up after the voice path settles.
- Current UI pass compiles; remaining work is product refinement, not syntax rescue.
- Direct Mode Slice 2 is still open: reminder/task capture, fuzzy-time resolution, optional Apple Reminders escalation, and location/travel timing.
- The Pi is healthy again, but wake word still depends on `PICOVOICE_ACCESS_KEY`, and TTS still falls back until `piper` plus the voice model are installed on-device.
- Realtime voice code is ready, but `OPENAI_API_KEY` is not configured on `pihub.local`, so the realtime path will report unavailable there until ops adds that env var.

## Parked
- `WebSocketSession` cleanup race
- `DashboardView` interaction and state audit
- responsive widget content system across all widgets
- kiosk snapshot sync endpoints + native push service
- deploy hardening to systemd-only restart/update flow

## People & Context
- Todd wants side-by-side Claude/Codex work to keep repo notes current.
- Before any new implementation continues, check current repo status and diffs first.
- Treat older rough summaries as historical context only; prefer live repo state plus this memory file.

## Recent Decisions
- The agreed roadmap is:
  - `v0.49.x`: smoothness, responsiveness, stability, interaction clarity
  - `v0.50.x`: real kiosk sync, helpfulness upgrades, deploy/boot polish
- The kiosk mic should ultimately talk to a Codex agent using instructions Todd will provide.
- Note upkeep is part of Definition of Done for each focused work batch.
- `docs/SESSION-START.md` is now the one-file fresh-session entry point. If Todd says `Let's work on Project Alfredo`, treat that as the cue to run the standard startup checks before editing.

## Next Step
- When work resumes, check the current build outcome first.
- If the UI pass compiles cleanly, continue with:
  - live spoken validation of kiosk realtime voice after `OPENAI_API_KEY` is configured on the Pi
  - native/iCloud-backed persistence for realtime-created tasks/reminders
  - location/travel actions
  - kiosk task/calendar/project sync beyond local state
