# alfredo HUD — design prototype

Terminal-style external-brain dashboard. Imported from a claude.ai/design handoff
([T_BrqFpg7W0jckba8CO2Rw](https://api.anthropic.com/v1/design/h/T_BrqFpg7W0jckba8CO2Rw))
on branch `design/alfredo-terminal-hud`. See `DESIGN_CHAT.md` for the full iteration log.

## Run it

```bash
./serve.sh          # http://localhost:8000
./serve.sh 8088     # or pick a port
```

Needs internet the first time (React/Babel/fonts come from unpkg + Google Fonts).

## Knobs to play with (TWEAKS panel, bottom-right)

| Control       | Options                                          |
|---------------|--------------------------------------------------|
| SURFACE       | KIOSK (1024×600) · MACOS (1280×800) · iOS (390×844) |
| PALETTE       | blue · phosphor (green) · amber · tokyo (purple) |
| FONT          | JetBrains Mono · IBM Plex Mono · Geist Mono      |
| CHROME        | CLEAN → OPERATOR → FULL HUD (slider)             |
| DENSITY       | DEFAULT · TIGHT                                  |
| CONFIDENCE    | DOT · % · FADE                                   |
| FOCUS MODE    | SPOTLIGHT · BLACKOUT · ZOOM                      |

State persists in `localStorage` under `alfredo:state` — clear it to reset.

## Interactions wired

- Click any priority in **DAILY.BRIEF** → focus overlay (ESC to exit)
- Click blank `◌` in **SCRATCH.PAD** → add a todo (Enter to commit, Esc to cancel)
- Click a scratch row → toggle done
- Type into **CLAUDE.TTY** and press Enter → deadpan reply
  - When served locally (no claude.ai runtime), a small canned-reply engine
    in `index.html` simulates the persona so the TTY stays playable.

## Files

| File              | Purpose                                                |
|-------------------|--------------------------------------------------------|
| `index.html`      | App shell, TWEAKS panel, focus overlay, offline TTY    |
| `styles.css`      | All visual styles (palettes, chrome variants, surfaces)|
| `data.jsx`        | Mock data: brief, pulse, calendar, inbox, projects     |
| `widgets.jsx`     | Pane chrome + each widget (DAILY.BRIEF, CALENDAR, etc.)|
| `surfaces.jsx`    | KioskSurface / MacosSurface / IosSurface compositions  |
| `DESIGN_CHAT.md`  | Design-session transcript (intent lives here)          |

## Porting to production

This is a React-in-a-single-HTML prototype. When adopting pieces into the
real app, match visual output — don't copy the prototype's structure:

- **Pi kiosk (`pi-kiosk/`)** — closest match. The palettes, pane chrome, and
  confidence dots could be lifted directly into `index.html`/`settings.html`.
- **iOS/macOS (Swift)** — use the design as a visual reference for new SwiftUI
  views. Ignore the JSX; match colors, spacing, and typography from `styles.css`.
