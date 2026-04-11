---
description: Start the day - load memory, pull calendar/email, ready to work
argument-hint: ""
allowed-tools:
  - Read
  - Write
  - Edit
  - Bash(date:*)
  - Bash(ls:*)
  - Bash(mkdir:*)
---

Start the work day. Loads context and gets ready to work.

## Source Files

- **Memory File**: `.claude/memory.md`
- **Daily Note Template**: `Templates/Daily Note Template.md`
- **Task Board**: `Task Board.md`
- **Daily Notes Folder**: `Daily Notes/`
- **Email Filter**: `Config/email-filter.md`

---

## Steps

### Step 1: Get today's date

Determine today's date in MMDDYY format.

### Step 2: Load Memory

Read the memory file.

If it has content in the "Now" or "Open Threads" sections, briefly surface the context:
- "Context from memory: [Now summary]"
- "Open threads: [list key items]"

If memory is empty/placeholder only, skip silently.

### Step 3: Create/Open Daily Work Note

Check if today's work note exists at:
`Daily Notes/MMDDYY.md`

If it doesn't exist:
1. Read the template from `Templates/Daily Note Template.md`
2. Replace template variables:
   - `{{DATE}}` → MMDDYY (today's date)
3. Create the new daily work note with the processed template

### Step 4: Open Task Board

Read the Task Board.

### Step 5: Process Inbox

If Inbox has items, ask for each: Today, Soon, Later, or delete?

### Step 6: Autonomous Context Gathering

**DO NOT ASK PERMISSION. Just pull and present.**

**Calendar:**
- Read today's Omnidian calendar (tmichel@omnidian.com)
- Format: "Calendar: 9:00 standup, 10:30 Namaste call, 2:00 BESS review"
- Identify open blocks: "Open blocks: 11:00-12:00, 3:00-5:00"

**Email:**
- Scan Gmail inbox for actionable items
- Apply filters from Config/email-filter.md (known contacts, urgent keywords, time-sensitive)
- Surface: "[EMAIL] From: sender - subject summary @scope"
- For each, ask: "Add to Inbox, respond now, defer, or dismiss?"
- If response needed: draft suggestion

**Note:** For Phase 1 implementation, if calendar/email APIs aren't set up yet, say: "Calendar and email auto-pull will be available once APIs are configured. For now, paste any actionable emails or calendar events."

**Keep this under 2 minutes total. Skip silently if nothing actionable.**

### Step 7: Cap Check

If Today has >5 items:
"You have [N] items today. Want to bump anything to Soon?"

### Step 8: First Steps

For each Today item, suggest one concrete smallest-first-step:
```
Today:
- [ ] Draft BESS scope for Reactivate NY
  > First step: Open the Gotion spec sheet and confirm container counts
- [ ] Review Namaste PM report
  > First step: Pull up the report and scan the executive summary
```

### Step 9: Yesterday's Wins

Check yesterday's Done list (look for yesterday's date in Daily Notes or Task Board Done section).

If Done list has items from yesterday:
"Yesterday: [1-2 key completed items]. Nice."

Skip if empty. Keep brief. Not patronizing.

### Step 10: Day Overview

Present calendar + tasks in one view:
```
Calendar: 9:00 standup, 10:30 Namaste call
Open blocks: 11:00-12:00, 3:00-5:00

Today:
- [ ] Draft BESS scope [src:email-041526] @work
  > First step: Open Gotion spec, confirm container counts
- [ ] Review PM report [src:cal-041526-meeting] @work
  > First step: Scan executive summary
```

**Then ask:** "What do you want to start with?"

---

## Notes

- Be concise
- Focused, action-oriented
- Skip any section silently if its source file is empty
- Target: under 3 minutes total
