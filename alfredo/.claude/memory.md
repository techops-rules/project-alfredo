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

## Open Threads
- Voice path: ROADOM mic / wake listener -> kiosk voice event queue -> kiosk overlay + native polling -> Alfredo/Codex agent handoff.
- Cross-surface UX plan is approved and waiting behind the current voice integration batch.
- Real native-to-kiosk sync is still a major follow-up after the voice path settles.
- Current UI pass compiles; remaining work is product refinement, not syntax rescue.

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

## Next Step
- When work resumes, check the current build outcome first.
- If the UI pass compiles cleanly, continue with:
  - kiosk task/calendar sync
  - richer Pi terminal content
  - follow-up widget density polish on native and kiosk
