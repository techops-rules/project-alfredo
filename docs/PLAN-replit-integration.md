# Plan: Replit Brief Integration
_Source: alfredo-claude-code-brief.md (iCloud) — Replit's design recommendations translated into a buildable spec_
_Created: 2026-04-10_

## Context

The `REPLIT-BRIEFING.md` was sent to Replit asking for UI/UX design recommendations for alfredo. Replit returned `alfredo-claude-code-brief.md` — a detailed React+TypeScript implementation spec (390×844px iPhone-frame, 9 widgets, Framer Motion). The reference file `artifacts/mockup-sandbox/src/components/mockups/alfredo/Alfredo.tsx` lives on Replit, not in this repo.

**Decision:** Don't rebuild in React/Vite. Extract the design improvements and apply them to:
1. **Pi kiosk** (`pi-kiosk/index.html`) — primary target, already web-based, highest visibility
2. **Swift app** (`Shared/Views/`) — secondary, apply matching improvements to iOS/macOS

---

## Phase 0 Audit Results (completed 2026-04-10)

- **Dot progress already implemented** in TODAY.EXE via `renderDots()` + `.today-dot`/`.today-dot.lit`. No X/Y counters exist anywhere. Phase 1a is largely done — skip or just verify.
- **Task badges** show "N open" text in widget header (minor, low priority)
- **Weather** has WMO codes + Open-Meteo wired. Location is **Seattle (47.61, -122.33)** — brief specifies Allentown (40.608, -75.490). Fix location in Phase 3.
- **Calendar** flat list only — no 3-state tap (Phase 2 work)
- **Hotlist widget** does not exist; tasks have no urgency field (`{text, done}` only) — needs schema addition for Phase 1b
- **Funfact, Waiting/Deferred modal** — not present (Phase 3/4)
- **Version** is `v0.42.11` in index.html. `deploy.sh` auto-reads it — bump before deploying.
- **Swift:** `ProgressDots` at `Shared/Views/Components/ProgressDots.swift` (takes `percent: Int`, 5 dots). Dashboard widgets need audit for X/Y usage (Phase 5).

---

## Phase 0: Current-State Audit

Before touching code, read the following to understand current implementations:

**Pi kiosk:**
- `pi-kiosk/index.html` — full file (811 lines). Identify: meetings widget, task list, habits, scratch, weather, status bar, hamburger menu
- `pi-kiosk/serve.py` — any data endpoints that feed widget content

**Swift app:**
- `Shared/Views/Dashboard/` — list all widget files
- `Shared/Views/Components/` — list all component files (ProgressDots already exists per REPLIT-BRIEFING.md)
- `Shared/Services/MeetingPrepService.swift` — understand briefing data structure
- `Shared/Models/Task.swift` — understand section/urgency fields

**Verification checklist:**
- [ ] List all widgets present in pi-kiosk index.html
- [ ] Confirm whether pi-kiosk has a weather widget and what WMO mapping it uses
- [ ] Confirm whether pi-kiosk has a meetings widget and what its tap behavior is
- [ ] Confirm whether pi-kiosk uses X/Y counters or dots for progress
- [ ] List Swift Dashboard widget files and which ones have progress indicators
- [ ] Confirm ProgressDots component location in Swift

---

## Phase 1: Pi Kiosk — Dot Progress + Hotlist Widget

**What:** Replace all X/Y number counters in the pi-kiosk with the dot-progress pattern. Also add the Hotlist widget (unified urgent tasks + events).

### 1a. Dot Progress (pi-kiosk)

Replace any `"2/5"` or `"X of Y"` counter text with a row of filled/empty dots.

Pattern from brief (translate to vanilla JS/CSS):
```js
function renderDotProgress(total, done, accentVar = '--accent') {
  return Array.from({ length: total }).map((_, i) =>
    `<span class="dot-prog ${i < done ? 'done' : ''}" style="
      width:7px; height:7px; border-radius:50%; display:inline-block; margin-right:4px;
      background: ${i < done ? 'var(' + accentVar + ')' : 'hsl(var(--accent-hsl)/0.18)'};
      transition: background 0.2s ease;
    "></span>`
  ).join('');
}
```

Apply to: habits header, tasks header, any progress summary.

**Verification:**
- [ ] Grep `index.html` for `"/"` patterns near task/habit counts — should be zero after update
- [ ] Visually confirm dots render at 1024×600 in Chrome

### 1b. Hotlist Widget

A unified urgent list mixing tasks (urgency=high/med) and today's calendar events, sorted by urgency then time. Each row:
- Urgency dot: filled accent = high, 55% opacity = med
- Item text + due time
- `personal` badge for personal-source items
- Tasks: animated checkbox toggle → strikethrough + fade to 28% opacity
- Events: hollow circle indicator

**Sample data structure** (until live data wired):
```js
const hotlistItems = [
  { type: "task",  text: "...", due: "Today",   urgency: "high", source: "work" },
  { type: "event", text: "...", due: "9:15 AM", urgency: "high", source: "work" },
  // ...
];
```

Sort: `high` before `med`, events sorted by time within urgency tier.

**Placement:** Replace or supplement the existing TODAY.EXE task list with this on screen 1 (or add as a new widget if layout allows within 1024×600).

**Verification:**
- [ ] Hotlist renders with correct dot colors
- [ ] Checkbox toggle adds strikethrough + fades item
- [ ] `personal` badge appears for personal items

---

## Phase 2: Pi Kiosk — Meetings 3-State Tap

**What:** The meetings widget currently shows a list. Update it so tapping a meeting cycles through 3 states:

1. **Collapsed** — title + time, "tap for brief" hint text (past meetings at 38% opacity)
2. **Brief** — one-sentence summary, animates open (CSS max-height transition)
3. **Full context** — detailed notes paragraph + if recurring, a "prev session" block separated by `<hr>`

Tap again from Full → Collapsed.

**Implementation (vanilla JS):**
```js
function cycleMeetingState(el) {
  const states = ['collapsed', 'brief', 'full'];
  const cur = el.dataset.state || 'collapsed';
  const next = states[(states.indexOf(cur) + 1) % states.length];
  el.dataset.state = next;
  el.querySelector('.meeting-brief').style.display = next !== 'collapsed' ? 'block' : 'none';
  el.querySelector('.meeting-full').style.display = next === 'full' ? 'block' : 'none';
  el.querySelector('.meeting-hint').style.display = next === 'collapsed' ? 'block' : 'none';
}
```

Use CSS `max-height` transition for the height animation (no Framer Motion needed):
```css
.meeting-detail { max-height: 0; overflow: hidden; transition: max-height 0.25s ease; }
.meeting-detail.open { max-height: 200px; }
```

**Data fields needed per meeting:**
- `title`, `time`, `endTime`, `past: bool`, `recurring: bool`
- `brief`: one-sentence string
- `longContext`: multi-sentence string
- `prevBrief`: string | null (only if recurring)

Wire to MeetingPrepService data if available via bridge endpoint; use sample data as fallback.

**Verification:**
- [ ] Tap cycles collapsed → brief → full → collapsed
- [ ] Past meetings render at 38% opacity when collapsed
- [ ] `rec` badge shows for recurring meetings
- [ ] Height animates smoothly

---

## Phase 3: Pi Kiosk — Weather WMO Emoji + Funfact

### 3a. Weather Widget WMO Mapping

Ensure the weather widget uses the full WMO code → emoji mapping from the brief:

```js
const WMO = {
  0: ['☀️','Clear'], 1: ['🌤','Mostly clear'], 2: ['⛅','Partly cloudy'],
  3: ['☁️','Overcast'], 45: ['🌫','Fog'], 48: ['🌫','Fog'],
  51: ['🌦','Drizzle'], 53: ['🌦','Drizzle'], 55: ['🌦','Drizzle'],
  61: ['🌧','Rain'], 63: ['🌧','Rain'], 65: ['🌧','Rain'],
  71: ['❄️','Snow'], 73: ['❄️','Snow'], 75: ['❄️','Snow'],
  80: ['🌦','Showers'], 81: ['🌦','Showers'], 82: ['⛈','Showers'],
  95: ['⛈','Thunderstorm'], 96: ['⛈','Thunderstorm'], 99: ['⛈','Thunderstorm'],
};
```

Open-Meteo endpoint (already in brief, no API key):
```
https://api.open-meteo.com/v1/forecast
  ?latitude=40.608&longitude=-75.490
  &current=temperature_2m,weather_code,wind_speed_10m
  &temperature_unit=fahrenheit&wind_speed_unit=mph
  &timezone=America/New_York
```

Display: emoji (22px) + temp °F (16px monospace accent) + condition label (7px) + wind (7px). Spinning loader while fetching.

### 3b. Funfact Widget

Small widget showing a random hardcoded fun fact on each load. Pattern:
```js
const FUNFACTS = [
  "Octopuses have three hearts and blue blood.",
  "A day on Venus is longer than a year on Venus.",
  // add 10–15 more
];
const fact = FUNFACTS[Math.floor(Math.random() * FUNFACTS.length)];
```

Display: `✦` glyph + 2-line clamped monospace text (9px). Place in the small 1-cell widget slot if layout allows.

**Verification:**
- [ ] Weather shows spinner then emoji+temp+condition
- [ ] WMO code 0 → ☀️ Clear, 61 → 🌧 Rain (spot check)
- [ ] Funfact changes on page reload

---

## Phase 4: Pi Kiosk — Waiting/Deferred Modal + Deploy

### 4a. Waiting/Deferred Widgets

Currently these may be simple counts or not present. Update to:
- **Collapsed:** large number count + label (e.g., "4 WAITING"), tappable
- **Expanded modal:** slides up (CSS transform transition), shows full list with overflow button, drag-down-to-dismiss at 80px threshold

```css
.modal-sheet {
  position: fixed; bottom: 0; left: 0; right: 0;
  background: #0a0f1a; border-top: 1px solid var(--accent-border);
  border-radius: 12px 12px 0 0;
  transform: translateY(100%); transition: transform 0.3s ease;
  z-index: 100;
}
.modal-sheet.open { transform: translateY(0); }
```

### 4b. Deploy

After all pi-kiosk changes:
```bash
cd /Users/todd/Projects/project\ alfredo
./pi-kiosk/deploy.sh
```

Then verify in Chrome at `http://pihub.local:8430/` at 1024×600 viewport.

**Verification:**
- [ ] Waiting/Deferred count tappable → modal slides up
- [ ] Modal dismisses on swipe/tap outside
- [ ] deploy.sh exits 0, kiosk page reloads on Pi

---

## Phase 5: Swift App — Matching Improvements

Apply the same design improvements to the native app.

### 5a. ProgressDots in Swift

`ProgressDots` component already exists (`Shared/Views/Components/`). Audit where X/Y number counters are still used in dashboard widgets and replace with `ProgressDots`. Key locations to check:
- `HabitsWidget` or equivalent
- `TaskListWidget` header
- `GoalsWidget`

### 5b. Meeting 3-State Collapse (Swift)

`MeetingBriefingSheet` (`Shared/Views/`) already has briefing data from `MeetingPrepService`. Add a 3-state toggle within `CalendarEventWidget` (or wherever calendar events render on the canvas):
- State 1: title + time only
- State 2: brief (1 sentence) — animate `.frame(height:)` with `.animation(.spring(response: 0.3, dampingFraction: 0.8))`
- State 3: full context + prev session block

Tap gesture on event row cycles state. Past events at 0.38 opacity.

### 5c. Hotlist / Urgency Sort

In the iOS Home tab or macOS dashboard task list, add urgency-sort: tasks with `isUrgent == true` surface first, then by section order. Mix in today's calendar events (already available via `CalendarService`). Use a `ForEach` over a merged sorted array.

**Verification:**
- [ ] Habits/Goals widgets show dots not numbers
- [ ] Calendar event rows cycle 3 states on tap
- [ ] Task list shows urgent tasks + today events interleaved, urgents first
- [ ] Build succeeds: `xcodebuild -project alfredo.xcodeproj -scheme alfredo-iOS -destination 'generic/platform=iOS' build`

---

## Anti-Patterns to Avoid

- **Don't add React/Vite** to this repo for the pi-kiosk — vanilla JS is sufficient and avoids a build pipeline
- **Don't use Framer Motion** — use CSS transitions (`max-height`, `transform`, `opacity`) for pi-kiosk animations
- **Don't invent new Swift APIs** — use existing `MeetingPrepService`, `CalendarService`, and `TaskBoardService` data
- **Don't break the deploy.sh flow** — always bump version and use `deploy.sh` per feedback memory
- **Don't use shame-based UI** — no "overdue" labels, no red counters on tasks (ADHD design principle from REPLIT-BRIEFING.md)

---

## Session Handoff Notes

Each phase can be executed in its own Claude Code session. Start each session by:
1. Reading this plan file
2. Reading the source brief: `/Users/todd/Library/Mobile Documents/com~apple~CloudDocs/alfredo-claude-code-brief.md`
3. Running the Phase 0 audit if starting a new surface (pi-kiosk vs Swift)
4. Checking `pi-kiosk/deploy.sh` before deploying to understand version bump convention

Phases 1–4 are pi-kiosk only (HTML/CSS/JS). Phase 5 is Swift only. They can be done in any order but Phase 0 audit must precede whichever surface you start on.
