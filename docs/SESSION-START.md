# Alfredo Session Start

Use this file as the one-file entry point for any brand-new Codex or Claude session.

## Trigger phrase

If Todd says:

`Let's work on Project Alfredo.`

Treat that as a cue to do the standard Alfredo startup check before making changes.

## Standard startup check

1. Run `git status --short --branch`
2. Read `docs/HANDOFF.md`
3. Read `alfredo/.claude/memory.md`
4. Read `docs/UI-BRIEFING.md`
5. Read `COWORK.md`
6. Inspect diffs in any subsystem that looks active before editing

## Current priority order

1. Voice input to Alfredo/Codex agent
2. Real native-to-kiosk sync
3. Cross-surface UX cleanup
4. Deploy and boot polish
5. Hue and later integrations

## Default assumptions

- Parallel Claude/Codex work is normal.
- Repo notes are more trustworthy than old chat summaries.
- Do not assume ownership of voice, kiosk, or dashboard files without checking live diffs first.
- Keep `docs/HANDOFF.md` and `alfredo/.claude/memory.md` current at the end of each focused work batch.

## Read these first if time is tight

1. `docs/HANDOFF.md`
2. `alfredo/.claude/memory.md`
3. `docs/UI-BRIEFING.md`

## If resuming implementation

- Confirm whether the current task is:
  - voice/agent integration
  - kiosk/native sync
  - layout/UI polish
  - deploy/ops work
- Then inspect only the relevant files and current diffs before editing.
