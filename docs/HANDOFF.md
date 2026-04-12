# Alfredo — Live Handoff

> For: Codex, Claude, or any other agent with repo access
> Maintained from live repo state
> Last refreshed: 2026-04-12
> Repo: `techops-rules/project-alfredo`

---

## What Alfredo is

Alfredo is Todd's ADHD operating system across three surfaces:

| Surface | Tech | Role |
|---------|------|------|
| iOS app | SwiftUI | portable capture, briefings, canvas |
| macOS app | SwiftUI | primary desktop control surface |
| Pi kiosk | HTML/JS + Python | always-on ambient dashboard + mic surface |

The design language is deliberate: dark terminal-style UI, JetBrains Mono, restrained motion, clear status states, and no shame-driven task framing.

---

## Live repo status

### Active in-flight work

There is parallel work in progress for **voice + Codex agent integration**. As of the latest refresh, the working tree includes active edits in:

- `Shared/App/alfredoApp.swift`
- `Shared/Views/Dashboard/TerminalWidget.swift`
- `Shared/Views/Sheets/SettingsSheet.swift`
- `Shared/Services/VoiceEventService.swift` (new)
- `pi-kiosk/index.html`
- `pi-kiosk/serve.py`
- `pi-setup/alfredo-wake.py`
- `pi-setup/alfredo-wake.service`
- `CLAUDE.md`
- `alfredo.xcodeproj/project.pbxproj`

### What that work does (completed 2026-04-11)

- Terminal defaults moved to **agent mode** (`ALFREDO.TTY`)
- Native app starts a **voice event polling service** (VoiceEventService.swift)
- Kiosk has **voice overlay UI**: toast, state bar, mute button, push-to-talk mic button
- Kiosk server exposes voice API: `/proxy/voice-event`, `/proxy/voice-mute`, `/proxy/voice-activate`
- Wake listener uses **Porcupine wake word + Piper neural TTS + push-to-talk**
- **Monday-inspired persona** loaded from `~/alfredo-kiosk/persona.md` per Codex request
- Voice events propagate to kiosk (visual), iOS (VoiceEventService → TerminalWidget), macOS (same)

### UI/UX Briefing

**Read `docs/UI-BRIEFING.md` for the full widget inventory, layout systems, data architecture, and improvement opportunities across all three surfaces.** This is the primary reference for interface work.

**Read `docs/SESSION-START.md` for the default fresh-session startup checklist.** If Todd says `Let's work on Project Alfredo`, treat that as the cue to run that checklist before implementation.

### Latest layout pass (2026-04-12)

A first cross-surface layout polish pass is now in progress in the working tree:

- iPhone top chrome was rebuilt into a clearer control/status strip with:
  - explicit mode label
  - live connection state summary
  - next-task / edit-state summary text
  - dedicated sync + menu actions
- iPhone canvas world size now derives from the actual flow layout instead of a fixed cramped height, and canvas panning is disabled while edit mode is active to reduce gesture conflicts.
- Kiosk widgets now classify themselves as `compact` / `regular` / `expanded` via `ResizeObserver`, and widget spacing/type density respond to real panel size instead of one fixed style.
- Kiosk work mode now surfaces `ALFREDO.TTY` next to `TODAY.EXE` instead of hiding the terminal completely.
- Kiosk terminal output now acts as a live system feed for bridge/task/layout/voice events instead of a static placeholder.
- No-signing validation builds completed for `alfredo-macOS` and `alfredo-iOS` with only pre-existing warnings (`CalendarService` deprecation, `MarkdownParser` let/var cleanup).

### Latest voice wiring pass (2026-04-12)

- Kiosk mic path now does real end-to-end handoff: record audio -> local Whisper transcription -> `alfredo-bridge` `/chat` in `agent` mode -> Codex reply via Piper TTS.
- One-shot HTTP bridge calls now accept `mode: "agent"` and apply `~/alfredo-kiosk/agent-prompt.txt` the same way the WebSocket path already did.
- Voice `command` events now carry the actual transcript instead of a placeholder, so kiosk and native terminal surfaces show what was spoken.
- `pi-kiosk/settings.html` and `pi-kiosk/README.md` now describe the live voice path instead of the old "speech-to-text TODO" note.

### Latest Direct Mode slice (2026-04-12)

- Direct Mode Slice 1 foundation is now in the tree across kiosk + native surfaces.
- Native app now has a shared `DirectModeSessionService`, `DirectModeContextService`, and `DirectModeSheet` for explicit multi-turn "Talk to Alfredo" sessions.
- iOS/macOS now expose Direct Mode as a first-class entry point from settings and the iPhone input bar instead of hiding it behind the terminal only.
- Kiosk voice transport now distinguishes `mode: "direct"` and `session` events, and kiosk context snapshots are pushed into `/proxy/direct-context` for the wake listener to use.
- `alfredo-wake.py` now supports explicit direct-mode start/stop phrases, session timeout/extension, session IDs, kiosk-side conversation history, and read-only context-aware direct turns routed through the agent bridge.
- Slice 1 is intentionally read-only: no reminder/task creation yet, no location/travel routing yet, and no Apple Reminders escalation yet.

### Coordination notes

Voice pipeline is stable and deployed. Files can be edited freely — no in-flight ownership lock. For voice behavior changes, update `persona.md` (personality) or `alfredo-wake.py` (mechanics). For kiosk UI, edit `pi-kiosk/index.html`. For native widgets, edit `Shared/Views/Dashboard/`.

---

## What this chat added

This thread established the current shared direction for the project:

1. The next broad product push is **cross-surface smoothness and clarity**, not a visual redesign.
2. Documentation and handoff hygiene are part of the work, not an afterthought.
3. Side-by-side Claude/Codex work must leave **live baton-pass notes** in the repo.
4. Before any new implementation resumes, agents should **check current repo status first** rather than trusting older summaries.
5. The kiosk mic should ultimately talk to a **Codex agent** with instructions Todd will provide.

---

## Agreed roadmap

### `v0.49.x` — Smoothness first

Focus on stability, responsiveness, and interaction clarity across iPhone, macOS, and kiosk:

- fix `WebSocketSession` cleanup race
- audit `DashboardView` ownership for `@State` + `@Observable`
- cancel terminal HTTP requests on dismiss
- make `UserDefaults` decoding safer
- add kiosk `localStorage` and `fetch()` error handling
- make widget content responsive with shared size classes and density rules
- tighten iPhone browse vs edit interactions
- improve iOS/macOS shell-level sync and state affordances
- improve kiosk settings ergonomics and explicit save/error states

### `v0.50.x` — Sync, helpfulness, ops

Focus on shared state and system polish:

- native-to-kiosk state sync via a shared `KioskSyncService`
- kiosk snapshot endpoints for pushed state
- more prominent `What Next` and quick capture across surfaces
- systemd-consistent kiosk deploy/update flow
- kiosk boot experience aligned with native boot tone

---

## Immediate priority stack

1. **Voice input to Codex agent**
   - ROADOM mic / wake flow on kiosk
   - event path into kiosk UI and native terminal surface
   - clean handoff into the Alfredo/Codex agent prompt
2. **Real native-to-kiosk data sync**
   - tasks, scratchpad, habits, goals, suggested next task
3. **Cross-surface UX cleanup**
   - responsive widgets, iPhone gesture cohesion, shell clarity
4. **Ops hardening**
   - deploy/update consistency, version/status surfacing

---

## Parallel work protocol

For any Claude/Codex side-by-side session:

1. Run `git status --short --branch` before editing.
2. Inspect diffs in touched subsystems before assuming ownership.
3. Update `docs/HANDOFF.md` when priorities, ownership, or active work changes.
4. Update `alfredo/.claude/memory.md` at the end of each focused work session with:
   - what changed
   - what is in progress
   - blockers or risks
   - exact next step
5. Update `COWORK.md` only when long-lived workflow or priority rules change.
6. Leave a short handoff note with:
   - owner
   - subsystem
   - status
   - files to inspect next
   - any do-not-overwrite warning

---

## Current baton-pass note

### Owner
Claude Code

### Subsystem
Voice input, wake listener, kiosk voice UI, voice event transport, terminal voice event display

### Status
Voice system complete and deployed as of 2026-04-12. Push-to-talk working, Piper TTS working, persona loaded. Porcupine wake word available but needs PICOVOICE_ACCESS_KEY.

Follow-up from Codex on 2026-04-12: the mic handoff now includes local Whisper transcription and agent-mode `/chat` requests, so push-to-talk reaches the Codex system prompt rather than a generic one-shot bridge prompt.

Direct Mode Slice 1 also landed on 2026-04-12: kiosk/native now have explicit multi-turn direct conversation scaffolding with shared session state and read-only context assembly for schedule, tasks, projects, and memory.

Next focus: **Direct Mode Slice 2** or broader cross-surface UX polish, depending on priority.
If continuing Direct Mode, the next batch is:

1. task/reminder capture from voice
2. fuzzy-time resolution like "later"
3. optional Apple Reminders escalation
4. location/travel timing

### Inspect next

- `docs/UI-BRIEFING.md` — full widget/layout/data briefing
- `pi-kiosk/index.html` — kiosk dashboard
- `Shared/Views/Dashboard/DashboardView.swift` — iOS/macOS canvas
- `Shared/Views/Dashboard/*Widget.swift` — individual widgets
- `Shared/Models/WidgetContentMetrics.swift` — responsive sizing

### Priority improvements

1. Pi kiosk task sync with native app (tasks are siloed in localStorage)
2. Pi kiosk live calendar data (currently stubs)
3. Extend the Pi terminal feed beyond bridge/voice/layout logs into richer task + system context
4. Habit/goal persistence (currently lost on app restart)
5. iOS manual mode override (force focus/meeting mode)
6. Consistent interaction patterns across surfaces

---

## Recommended resume sequence

When work resumes:

1. re-check `git status`
2. inspect the current voice/agent diffs
3. confirm build/runtime health for native and kiosk pieces
4. decide whether the next change belongs in the voice path or in untouched UX/sync files
5. only then resume implementation
