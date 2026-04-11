---
name: kiosk-tweak
description: >
  Edit, rearrange, and style the alfredo Pi kiosk dashboard (pi-kiosk/index.html).
  Use this skill whenever the user wants to tweak the kiosk, change widget layout,
  move widgets around, add/remove widgets, change colors or styling, adjust the
  kiosk UI, or mentions "kiosk" in the context of visual changes. Also trigger when
  the user says things like "move the calendar widget", "make the tasks bigger",
  "add a new widget", "change the kiosk colors", or "rearrange the dashboard".
---

# Kiosk Tweak

You are editing the alfredo Pi kiosk — a 1024x600 dashboard displayed on a ROADOM 7" IPS screen connected to a Raspberry Pi. All edits happen in `pi-kiosk/index.html` (a single-file HTML app with inline CSS and JS).

## Architecture at a glance

The kiosk is a single HTML file with three key regions:

1. **CSS** (lines 6–272): All styles including `:root` variables, widget classes, animations
2. **HTML widgets** (lines 276–450): Each widget is a `<div class="widget" id="w-NAME">` with inline `style` for position/size
3. **JS layouts object** (~line 1051): `const layouts = { ... }` defines named presets (default, default-md, default-lg, focus, terminal) that override widget positions

### Current widgets

| ID | Name | Purpose |
|----|------|---------|
| `w-clock` | CLOCK.SYS | Time, date, fun fact |
| `w-weather` | WEATHER.SYS | Current conditions + forecast |
| `w-work` | WORK.TODO | Work task list |
| `w-life` | LIFE.TODO | Life task list |
| `w-cal` | CALENDAR.DAT | Today's calendar events |
| `w-today` | TODAY.EXE | Progress dots + waiting/deferred counts |
| `w-hotlist` | HOTLIST.EXE | Urgent/priority items |
| `w-stats` | STATS.DAT | Streak, completed, focus time |
| `w-scratch` | SCRATCH.PAD | Quick notes |
| `w-tty` | CLAUDE.TTY | Terminal bridge to Claude Code |

### Canvas constraints

- **Screen**: 1024px wide x 600px tall (minus 28px status bar = 572px usable)
- **Coordinate system**: Widgets use absolute positioning (`left`, `top`, `width`, `height` in px)
- **Some widgets use `right` instead of `left`** (e.g., w-today, w-weather in some layouts)
- **Status bar**: Fixed 28px at bottom, not editable via layouts
- **Font scaling**: Three layout tiers (default <=13px, default-md 14-15px, default-lg 16px+) auto-selected by font size

## How to make changes

### Moving or resizing widgets

You must update **two places** for every position/size change:

1. **Inline HTML `style`** on the widget `<div>` — this is the initial/fallback position
2. **`const layouts` JS object** — every layout preset that shows the widget needs updated coordinates

If you only update one, the widget will snap to the wrong position when layouts are applied or on page load.

**Example — move WORK.TODO down by 20px:**

```
// 1. HTML inline style
<div class="widget" id="w-work" style="left:16px;top:150px;width:310px;height:210px">
                                              ↑ was 130px

// 2. In layouts object, update EVERY preset that has w-work:
default:    { 'w-work': {left:'16px', top:'205px', ...} }   // was 185px
default-md: { 'w-work': {left:'16px', top:'198px', ...} }   // was 178px
// etc.
```

### Adding a new widget

1. Add the HTML `<div class="widget" id="w-NEWNAME" style="...">` inside `<div class="canvas">`
2. Add CSS styles for the widget content
3. Add the widget ID to every layout preset in `const layouts` (either `{show:true, left:..., top:..., width:..., height:...}` or `{show:false}`)
4. Add any JS logic (data loading, rendering) in the `<script>` section

### Changing colors or styling

- Global colors live in `:root` CSS variables (line ~9)
- Widget-specific styles are in the `<style>` block
- The accent color is `--accent: #61AFEF` — changing this affects borders, headers, highlights globally

### Toggling widget visibility

In the layouts object, set `show: false` to hide a widget in that preset. The `hidden` CSS class is applied automatically by `applyLayout()`.

### Version bumping

The version string is in the status bar HTML (look for `v0.XX.X` near line 382). Bump the patch number for small tweaks, minor for layout changes.

## Workflow

After making all edits to `pi-kiosk/index.html`:

1. **Bump the version** in the status bar span
2. **Preview locally** — serve the file and check at 1024x600:
   ```bash
   cd "pi-kiosk" && python3 -m http.server 8431
   ```
   Then use Claude Preview or open in Chrome at 1024x600 viewport to verify.
3. **Deploy to Pi** — run the deploy script:
   ```bash
   bash pi-kiosk/deploy.sh
   ```
   This diffs, syncs changed files, reloads the kiosk browser, and verifies services.

Always deploy after editing. Local edits don't reach the Pi until `deploy.sh` runs.

## Snap grid reference

When positioning widgets, use these alignment guides for the 1024x600 canvas:

- **Left margin**: 16px
- **Right margin**: 16px (or use `right: '16px'`)
- **Top margin**: 8px
- **Row gaps**: ~12px between widget rows
- **Column gaps**: ~12px between side-by-side widgets
- **Status bar**: 28px fixed at bottom (so max widget bottom = ~564px)
- **Common column splits**:
  - Two equal columns: left=16px w=494px | left=522px w=486px
  - Thirds: ~326px each with 12px gaps
  - Left sidebar + main: left=16px w=300px | left=328px to right=16px

## Design language

The kiosk uses a terminal/hacker aesthetic:
- Font: JetBrains Mono
- Dark background (#080E18) with subtle grid overlay
- Widget headers: ALL CAPS, 10px, accent-colored, letter-spacing: 2px
- Naming convention: `NAME.EXT` format (CLOCK.SYS, WORK.TODO, etc.)
- Status indicators: colored dots (green=on, yellow=warn, red=off)
- Interactions: tapping, long-press for detail sheets, triple-tap clock to exit
