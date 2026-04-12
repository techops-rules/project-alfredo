# alfredo — Cowork Context

Read this at the start of a Cowork session. It explains what Alfredo is, how Todd uses it, and how to work safely alongside Claude Code or Codex.

---

## What is alfredo?

Alfredo is Todd's personal productivity dashboard and ADHD operating system.

It runs on three surfaces:

1. **iOS app** — mobile capture and briefings
2. **macOS app** — primary desktop command centre
3. **Pi kiosk** — always-on dashboard and mic surface beside the desk

The visual system is intentional: terminal-style, low-shame, low-friction, dark, calm, and clear.

---

## How Todd works with agents

- **Cowork is the planning and decision surface.**
- **Claude Code and Codex are execution partners.**
- **Context lives in repo files.** The task board, scratchpad, memory, and handoff docs matter more than chat history.
- **Parallel work happens.** Always check current repo status before assuming you own a subsystem.

---

## Project location

```
~/Projects/project alfredo/
  CLAUDE.md
  COWORK.md
  alfredo/
    Task Board.md
    Scratchpad.md
    .claude/memory.md
  docs/
    HANDOFF.md
    CONTEXT.md
    CODEX-AGENT-ALFREDO.md
  Shared/ iOS/ macOS/
  pi-kiosk/
  pi-setup/
  alfredo.xcodeproj/
```

**GitHub:** `techops-rules/project-alfredo`
**Pi:** `todd@pihub.local`
**Dashboard:** `http://pihub.local:8430/`
**Settings:** `http://pihub.local:8430/settings.html`

---

## Current priority order

1. **Voice input to Alfredo/Codex agent**
2. **Real native-to-kiosk sync**
3. **Cross-surface UX cleanup**
4. **Deploy and boot polish**
5. **Hue and later integrations**

The currently approved roadmap is:

- `v0.49.x`: smoothness, stability, responsiveness, interaction clarity
- `v0.50.x`: kiosk sync, helpfulness upgrades, deploy/boot polish

---

## Parallel work rule

Before recommending implementation or taking ownership of a coding task:

1. check `git status`
2. read `docs/HANDOFF.md`
3. read `alfredo/.claude/memory.md`
4. inspect diffs in any subsystem that looks active

If Claude or Codex is already in a subsystem, leave a baton-pass note instead of assuming it is safe to overwrite.

---

## Stable product truths

- SwiftUI only for native surfaces
- markdown files are the source of truth
- iCloud documents are the native sync layer
- terminal aesthetic is an ADHD accommodation, not decoration
- no shame UI
- short, direct, useful language beats flourish

---

## What is happening right now

- Voice/mic integration is actively being built in parallel.
- The kiosk is becoming the ambient mic surface.
- The terminal and agent flow are being aligned around **ALFREDO.TTY** and the Codex system prompt.
- Broader UX cleanup work is approved but should resume only after checking the live repo state.

---

## Files to read first in a fresh session

1. `alfredo/Task Board.md`
2. `alfredo/.claude/memory.md`
3. `alfredo/Scratchpad.md`
4. `docs/HANDOFF.md`

---

## Keep this file current when

- long-lived workflow rules change
- priority order changes
- the collaboration pattern between Cowork, Claude Code, and Codex changes
