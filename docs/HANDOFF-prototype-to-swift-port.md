# Handoff — Browser Prototype → Swift Port

**Date:** 2026-04-18
**Branch:** `design/alfredo-terminal-hud`
**Status:** Prototype feature-complete (except a few deferred items). Swift port in early stages.

## The two codebases

| Surface | Where it lives | Status |
|---|---|---|
| **Browser prototype** | `design/alfredo-hud/` (served on `localhost:8765` via `./serve.sh`) | Feature-rich, feedback-driven iteration target |
| **iOS Swift app** | `iOS/`, `Shared/`, `alfredo.xcodeproj` | Still running mostly pre-design-session code |
| **macOS Swift app** | same `Shared/` codebase | same state as iOS |
| **Pi kiosk** | `pi-kiosk/` | Separate HTML/CSS; untouched this session except for the MarkdownParser crash fix that's shared |

The prototype is where Todd gave UI/UX feedback. The Swift apps haven't been ported yet — they still render the pre-session design.

## What's in the prototype that the Swift apps DON'T have

Prioritized by visibility and user impact:

### Tier 1 — User has explicitly noticed the gap
1. **Weather hero** (iOS) — day/date top-left, sun/moon with moon phase shadow top-right, temp centered on sun (mono font, matches headline), weather description + Monday-voice quip ("rain all day · sad song day"), stars at night, horizon silhouette, thunderstorm lightning, radial sky gradient with day/night variants, heavy text-shadow readability. Existing `WeatherWidget.swift` is a different composition (dome arc + hour strip) and doesn't have the hero aesthetic.
2. **Rotating headline** — cycles through ~16 lines ("less thinking, more doing.", "the list doesn't shrink by staring at it.", etc.) every 22s, optionally refreshed by Claude every 4h. Lives in `design/alfredo-hud/data.jsx` as `HEADLINES`.
3. **Micro-facts ticker** — 8 deadpan facts rotating every 6s ("you slept 5h 12m. brace.", etc.). Fresh LLM-generated variants every 2h when an API key is set.

### Tier 2 — Core operator features
4. **Priority system (P0–P4)** — parse from note suffix/prefix, Sonnet-based auto-suggest with full context, P0 cap at 5 with triage modal, visual chips across all item types. See `design/alfredo-hud/triage.jsx` `PRIORITY_META` + `parsePriority` + `suggestPriorityLLM`.
5. **Scratch triage** — entity regex (phones, addresses, URLs, dates), rule+LLM hybrid classifier, tap-to-inspect modal with reclassify/approve/delete. Routes to mock stores (`todos`, `projectTasks`, `approvals`).
6. **Alfredo-action chat** — α·ACTION classification opens a live chat panel with streaming Claude, model picker (Haiku/Sonnet/Opus), markdown link rendering, per-item persistent transcript. Triggered by "alfredo", "help me", "find me", etc. phrasings.
7. **Proactive suggestions** — `generateSuggestions()` fires on mount + every 30min, produces synthetic alfredo-sourced scratch items with distinct α-prefix visual.
8. **Inbox reader + AI composer** — tap any email → modal with SUGGEST REPLY (streaming), WRITE MY OWN (preserves draft), DICTATE (Web Speech API), IMPROVE via Claude (polish dictation). CLEAR TEXT + SAVE DRAFT + DISCARD on close. Undo send (3s) + whoosh + sent folder.
9. **Text (SMS) composer** — same pattern for SMS; opened from phone entity SMS action.
10. **Draft sync** — email drafts to `localStorage alfredo:mailDrafts`, texts to `alfredo:textDrafts`.

### Tier 3 — Substantial but scoped
11. **Calendar event editor** — tap any event → inspector (edit title/time/location, tag manager, hide, delete); hidden events dim + collapse with "show N hidden" toggle. Overrides persist in `localStorage`.
12. **Projects with swipe actions** — iOS-style: swipe left → TRASH (red), swipe right → ARCHIVE (amber). Filter pills (ACTIVE/ARCHIVE/TRASH). `+ NEW PROJECT` button. Trash has RESTORE.
13. **Recursive nested subtasks** — `SubtaskTree` component renders tasks → subtasks → sub-subtasks ad infinitum. Each level: add-child (+), expand notes (▸), delete (×), check-off (◉).
14. **Collapsible panes** — tap any pane title → body hides, caret rotates, siblings reflow up. Per-surface state persisted.
15. **Sketch editor** — + DRAW mode → click-drag on surface to size a rect, modal for label + description. ✎ EDIT mode → drag handle to move, corner to resize. EXPORT JSON for porting to real widgets.
16. **Night/weekend/focus/meeting mode styling** — body class `mode-*` with visual shifts (night dims + cools, weekend warms + hides urgent states, focus fades non-primary cols). Auto-resolves from time + day; manual override.
17. **Undo snark** — Monday-voice lines shown below the undo countdown. 12 seed lines.
18. **Global themed toast + confirm + picker** — `window.alfToast(msg, {tone})`, `window.alfConfirm(msg, onYes, onNo)`, in-theme inline picker for reclassify selections. **All native `alert/confirm/prompt` calls have been eliminated.**

### Tier 4 — Polish features
19. **Copy buttons** on every TTY/chat message (hover on desktop, 50% on touch).
20. **Direct Anthropic API streaming** via `streamClaude` helper (SSE parsing, prompt caching). API key input in TWEAKS with TEST button.
21. **TTY bias-for-action** persona prompt rewrite — "no general advice, every reply ends in a concrete next move".
22. **Tweaks panel** — palette (blue/phosphor/amber/tokyo), mono font selector, chrome intensity slider, density, confidence viz, focus variant, mode auto/manual, surface switcher (kiosk/macos/ios).

### Tier 5 — Architectural support the Swift port will need
- A generic undo-toast pattern (email + text) with the 3-second commit window
- A stores model: `{ todos: [], projectTasks: { [name]: [] }, approvals: [], trash: [] }`
- A scratchpad triage pipeline (entity regex → rule classifier → LLM upgrade → route)
- A per-item persistent chat thread (for alfredo-action)
- Holiday computation (already done in Swift — see `Shared/Data/HeroCopy.swift`)

## What's already begun on the Swift side

- `Shared/Data/HeroCopy.swift` — HEADLINES + US holiday computer + `describeDay()` weather quip helper. `microFacts` intentionally empty until a real data source or LLM refresh lands.
- `MarkdownParser.parseTaskBoard` crash fix — `dropFirst(6)` replaces the unsafe `index(offsetBy:6)`. Shipped.
- New app icon in `Resources/Assets.xcassets/AppIcon.appiconset/`. Shipped.

### Shipped 2026-04-18 (this branch, `design/alfredo-terminal-hud`):
- **Weather Hero** (`Shared/Views/Dashboard/WeatherHero.swift`) — full iOS port of the prototype's IosHero: day/date, sun/moon with phase, mono temp centered on body, Monday-voice weather quip, star field at night, horizon silhouette, thunder lightning, rain/snow, day/night radial gradient.
- **RotatingHeadline** + **MicroFactsTicker** — Swift rotators for `HeroCopy`. LLM refresh hooks stubbed (awaiting Swift `ClaudeService`).
- **News widget** (`Shared/Views/Dashboard/NewsWidget.swift`) — pulls NYT + BBC + HN via a Foundation-only RSS parser. Rotates per-source every 22s. Manual refresh button in widget header.
- **NewsStorySheet** — tap-to-open detail modal: source, dateline, feed summary, and four actions: OPEN AT SOURCE, GOOGLE IT, ASK CLAUDE (POSTs structured prompt to Pi bridge `/chat`), SAVE FOR LATER.
- **ReadingListService** (`Shared/Services/ReadingListService.swift`) — JSON-backed saved-headlines store in `Documents/reading-list.json`.
- **ClaudeBridgeClient** (`Shared/Services/ClaudeBridgeClient.swift`) — minimal `/chat` helper for the Pi bridge. First Swift caller for the bridge's chat endpoint.
- **Weather location picker** — `WeatherService` default is now Allentown PA 18104 (40.5994, -75.5394), overridable via `UserDefaults`. `LocationPreferences` service geocodes zip/city queries (`CLGeocoder`) or resolves current location (`CLLocationManager`). `WeatherLocationSection` UI lives in the SettingsSheet. `NSLocation*UsageDescription` added to iOS + macOS plists.
- **Placeholder purge:**
  - `StatsWidget` now derives from `TaskBoardService` + habits + scratchpad; empty-state when no data.
  - `HeroCopy.microFacts` emptied; ticker hides when pool is empty.
- **iOS flow layout:** news slot lives directly under Hotlist on screen 1 (all contexts). Weather slot grew from 130 → 210pt to fit the hero.

## Sprint N+1 — Priority rework + universal detail popover + reorder gesture

Spec'd by user on 2026-04-18. Substantial enough to be its own session(s).

**Priority model — reduced to 4 tiers, renamed to 2-digit labels:**
- `00` (was P0) — critical, top of the day
- `01` (was P1) — very important
- `02` (was P2) — important
- `03` (was P3) — next-up
- (P4 removed — anything below `03` is unnumbered)

Store in `Task.priority` as an enum `Priority: Int { case p00, p01, p02, p03, unranked }`. Migrate existing P0–P4 reads — map P4 → unranked.

**Hotlist widget:**
- Each card shows its priority tag at left: `00 01 02 03` in mono, color-coded (the existing P-meta palette). Unranked cards show no number.
- Each card is **collapsible to a title bar** (tap the card chrome, or a chevron). Collapsed state persists per-item in `UserDefaults`.
- **Double-tap** a card → universal detail popover (see below).
- **Long-press** any hotlist card → full-screen reorder view:
  - Up to 8 cards total, all collapsed-card style.
  - Top 4 slots are the numbered priorities (00–03); remaining 4 are unnumbered.
  - Drag-to-reorder. Moving a card into slot 00 pushes what was there to 01, 01 → 02, 02 → 03, 03 → first unnumbered. Cascade is a simple shift, not a swap.
  - Dragging a numbered card down past slot 03 drops its number.
  - Dragging an unnumbered card up to slot 03 (or higher) assigns the new number and cascades.

**Universal detail popover (double-tap on any item across the app):**
A shared `ItemDetailSheet` that any widget can present. Fields:
- Title (editable)
- Tags (chip input)
- Reminder (date + time picker → writes to `UNUserNotificationCenter`)
- Subtasks (recursive — the prototype's `SubtaskTree`)
- Notes (freeform markdown)
- Priority (picker: 00 / 01 / 02 / 03 / unranked)
- Delete

Widgets that should wire this up: HotlistWidget, TaskListWidget (all variants — work/life/deferred/waiting/longterm), HabitWidget, GoalsWidget, ProjectsWidget, ScratchpadWidget items.

**Completion behavior (confirmed with user 2026-04-18):** when a numbered card is completed, **auto-promote** — the completed item loses its number and everything below shifts up (03 → 02, etc.). Slot does not stay sticky/empty.

**Suggested split:**
1. Session A: Priority refactor (`Priority` enum, parser, migration, chip rendering across task-bearing widgets). Ships the new `00/01/02/03` labels.
2. Session B: Universal `ItemDetailSheet` — double-tap behavior wired to Hotlist first, then extended.
3. Session C: Long-press reorder modal for Hotlist. Drag-shift cascade + auto-promote on completion. Persists to `TaskBoardService`.

**Ordering note (user, 2026-04-18):** Session C (Hotlist reorder) is the higher-value ship. Collapse-reflow refactor of `DraggableWidgetContainer` + `flowPosition`/`flowExtent` can land before or after C — user's call. It's worth doing before C only if the collapsed-card visual the reorder modal reuses needs the layout fix to look right.

Tie-in: this subsumes the "add-to-widget" gap — the detail popover is also where mobile users create new items per widget.

## Recommended port order (for the next session)

Start where the user has explicitly noticed the gap:

1. **Session 1: Weather Hero + Rotating Headline + MicroFacts (Swift)** — this is what Todd currently sees and calls "the old version". Deliverables:
   - New `Shared/Views/Dashboard/WeatherHero.swift` — SwiftUI port of the iOS hero
   - New `Shared/Views/Dashboard/RotatingHeadline.swift`
   - New `Shared/Views/Dashboard/MicroFactsTicker.swift`
   - Either replace or augment `WeatherWidget.swift`
   - Wire into `DashboardView.swift` (visible immediately on app launch)
   - Build + push

2. **Session 2: Priority system (data model + UI)** — `Priority` enum, `parsePriority()`, `Classifier+Priority` extension, suggest via existing `ClaudeService` using Sonnet. Add chip rendering to TaskListWidget / HotlistWidget / ProjectsWidget.

3. **Session 3: Scratchpad triage** — extend `ScratchpadService` with entity detection + classification. New `ScratchpadInspector.swift`. Route to `TaskBoardService` + a new `ApprovalsService` for calendar proposals.

4. **Session 4: Alfredo-action chat** — new `ActionChatService` with persistent per-item threads. Streaming via existing API client. Model picker UI.

5. **Session 5: Inbox AI composer** — if/when a real Mail integration lands; currently the iOS app doesn't surface inbox at all.

6. **Session 6: Calendar event editor + Projects swipe actions + recursive subtasks** — UI heavy but all patterns exist in the prototype.

## Files in the browser prototype (reference source-of-truth)

| File | Lines | Contains |
|---|---|---|
| `design/alfredo-hud/index.html` | ~2200 | App shell, all inspectors/modals, App state, streamClaude, UndoToast, SubtaskTree, ProjectInspector, EventInspector, AlfredoActionPanel, P0CapModal, ScratchInspector, ReclassifyRow, CopyButton, ACTION_MODELS, toast/confirm system |
| `design/alfredo-hud/widgets.jsx` | ~1100 | Pane + CollapseContext + all widgets (DailyBrief, CalendarPane, InboxPane, ProjectsPane, ScratchPane, PulsePane, TTYPane, WeatherPane, IosHero, RotatingHeadline, MicroFactsTicker), getHoliday + describeDay |
| `design/alfredo-hud/surfaces.jsx` | ~210 | KioskSurface, MacosSurface, IosSurface layouts |
| `design/alfredo-hud/triage.jsx` | ~300 | parsePriority, PRIORITY_META, P0_CAP, classifyNote, ruleClassify, llmClassify, suggestPriorityLLM, generateSuggestions, detectEntities, CLASS_BADGE, CAL_LABEL, ageState |
| `design/alfredo-hud/data.jsx` | ~230 | All seed data (HEADLINES, MICRO_FACTS, SCRATCH, INBOX, PROJECTS, CALENDAR, DAILY_BRIEF, TTY_GREETINGS) |
| `design/alfredo-hud/styles.css` | ~1700 | Full design system (palettes, panes, all modals, inspectors, swipe rows, chat, priority chips, themed popups) |

## Running the prototype

```bash
cd design/alfredo-hud && ./serve.sh
# → http://localhost:8765
```

## Notes for the next implementer

- The prototype's `window.claude.complete` is stubbed locally (see `index.html`). Real streaming uses `window.streamClaude` which hits Anthropic directly with the user's key from localStorage (`alfredo:anthropic_key`). When porting, use the existing `ClaudeService` (Pi bridge) or wire a direct API client.
- Priority auto-suggest uses **Sonnet 4.6** specifically; user explicitly requested that upgrade. Low-priority decisions should err on the side of lower priority ("prefer to err lower").
- Holiday computation is already ported in `HeroCopy.swift` — reuse.
- All user-facing copy should be lowercase and Monday-voice. Search `deadpan`, `mildly mean`, `persona` in the prototype to find the tone anchors.
- When the port lands a feature that maps to a prototype store (`stores.todos`, `stores.approvals`, etc.), make sure the existing Swift service (TaskBoardService, CalendarService) is the single source of truth — don't parallel-structure.
