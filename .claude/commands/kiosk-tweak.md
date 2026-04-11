You are editing the alfredo Pi kiosk — a 1024x600 dashboard on a ROADOM 7" screen connected to pihub.local. All edits happen in `pi-kiosk/index.html` (single-file HTML with inline CSS + JS).

## Your task

The user wants to tweak the kiosk. Read `pi-kiosk/index.html` and make the requested changes. Follow the rules below precisely.

## Architecture

The kiosk HTML has three regions:
1. **CSS** (~lines 6–272): `:root` variables, widget classes, animations
2. **HTML widgets** (~lines 276–450): `<div class="widget" id="w-NAME" style="...">` with inline positioning
3. **JS layouts** (~line 1051): `const layouts = { ... }` — named presets that override widget positions at runtime

### Widgets

| ID | Name | Shows |
|----|------|-------|
| `w-clock` | CLOCK.SYS | Time, date, fun fact |
| `w-weather` | WEATHER.SYS | Weather + forecast |
| `w-work` | WORK.TODO | Work tasks |
| `w-life` | LIFE.TODO | Life tasks |
| `w-cal` | CALENDAR.DAT | Calendar events |
| `w-today` | TODAY.EXE | Progress dots, waiting/deferred |
| `w-hotlist` | HOTLIST.EXE | Urgent items |
| `w-stats` | STATS.DAT | Streak, completed, focus |
| `w-scratch` | SCRATCH.PAD | Quick notes |
| `w-tty` | CLAUDE.TTY | Terminal to Claude Code |

### Canvas: 1024x600

- Usable height: 572px (600 minus 28px status bar)
- Left/right margin: 16px
- Top margin: 8px
- Widget gaps: ~12px
- Two-column split: left=16px w=494px | left=522px w=486px

## Critical rules

### 1. Update BOTH places for position/size changes

Every widget position exists in TWO places. You MUST update both:
- **Inline `style=` on the HTML `<div>`** — initial/fallback
- **Every layout preset in `const layouts`** that shows the widget

If you only update one, the widget will be wrong on load or when switching layouts.

### 2. Layout presets to update

There are 6 presets: `default`, `default-md`, `default-lg`, `focus`, `terminal`, and any custom ones. When changing a widget's position, update it in ALL presets where `show:true`. Presets with `show:false` for that widget can be left alone.

### 3. Version bump

Find the version string in the status bar (search for `v0.` near line 382). Bump the patch number (e.g., v0.46.0 → v0.46.1).

### 4. Deploy after changes

After all edits, run:
```bash
cd "/Users/todd/Projects/project alfredo" && bash pi-kiosk/deploy.sh
```

This syncs to the Pi and reloads the kiosk automatically.

## Design language

- Font: JetBrains Mono
- Background: #080E18, subtle grid overlay
- Widget headers: ALL CAPS, letter-spacing 2px, accent color
- Widget names: `NAME.EXT` format (CLOCK.SYS, WORK.TODO)
- Accent: `--accent: #61AFEF` (used for borders, headers, highlights)
- Status dots: green=on, yellow=warn, red=off

## Adding a new widget

1. Add `<div class="widget" id="w-NEWID" style="left:Xpx;top:Ypx;width:Wpx;height:Hpx">` inside `<div class="canvas" id="canvas">`
2. Give it a header: `<div class="widget-header">NAME.EXT <span class="zone">primary</span></div>`
3. Add a body: `<div class="widget-body">...</div>`
4. Add CSS for its content in the `<style>` block
5. Add to ALL layout presets in `const layouts` — `show:true` with position, or `show:false`
6. Add JS logic in `<script>` if needed

## Preview workflow

Before deploying, verify changes look right at 1024x600. Use Claude Preview if available, or:
```bash
cd "/Users/todd/Projects/project alfredo/pi-kiosk" && python3 -m http.server 8431
```
Then check at http://localhost:8431 in a 1024x600 viewport.

## User's request

$ARGUMENTS
