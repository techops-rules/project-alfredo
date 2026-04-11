---
description: Mid-day sync - review daily note, update memory, process inputs
argument-hint: ""
allowed-tools:
  - Read
  - Edit
  - Glob
  - Grep
  - Bash(date:*)
---

Sync memory with current daily work note and process any new meeting transcripts. Use mid-day or whenever context needs refreshing.

## Source Files

- **Memory**: `.claude/memory.md`
- **Daily Work Note**: `Daily Notes/MMDDYY.md`
- **Meetings Folder**: `Meetings/`
- **Scratchpad**: `Scratchpad.md`
- **Email Filter**: `Config/email-filter.md`

---

## Steps

### Step 1: Get today's date

Determine today's date in MMDDYY format.

### Step 2: Read current state

Read:
1. Today's Daily Work Note
2. Current Memory file
3. Scratchpad

### Step 3: Process unprocessed meetings

Scan the Meetings folder for any files with `status: unprocessed` in frontmatter.

For each unprocessed meeting:
1. Read the Raw Transcript section
2. Generate and fill in:
   - **Summary**: 2-4 sentence overview
   - **Action Items**: Bulleted list with owners if mentioned
   - **Key Points**: Important decisions, insights, information
3. Update frontmatter: `status: processed`
4. **Rename the file** to: `YYYY-MM-DD [Meeting Title].md`
   - Use date from frontmatter
   - Extract title from heading or create from summary
   - Use `mv` command to rename
5. Add to Daily Work Note under `## Meetings & Conversations`:
   - Format: `- [[Meeting Note Name]]: [one-line summary]`
   - Use the NEW filename (without .md) in wiki link
6. **ASK**: "Any action items from [meeting] you want moved to the Task Board?"
   - Do NOT auto-add action items
   - Only add if explicitly requested
   - Task Board is for needle-moving items only

### Step 4: Process Scratchpad

Read the Scratchpad. For each item:
1. **Tasks/todos** → Ask if they should go to Task Board Inbox
2. **Ideas/thoughts** → Add to Daily Note under Notes, or promote to Memory (Parked)
3. **Context/decisions** → Promote to Memory (appropriate section)
4. **Links/references** → Add to Daily Note under Notes
5. **Ephemeral/done** → Discard

After processing, summarize what was captured and where.

**Note:** Do NOT clear the scratchpad during /sync - only /wrap-up clears it.

### Step 5: Autonomous Context Check

**Calendar & Email:**
Same as /start Step 6. Pull calendar and email automatically.
Surface new actionable items. Keep under 1 minute.

### Step 6: Identify what to promote

Review Daily Work Note and Scratchpad for things to add to memory:
- Important decisions → Recent Decisions
- Open questions/blockers → Open Threads
- Ideas to revisit later → Parked
- People context learned → People & Context
- Priority shifts → Now

### Step 7: Identify what to prune

Review Memory for items that are:
- **Resolved** → Remove from Open Threads
- **No longer relevant** → Remove entirely
- **Completed decisions older than 2 weeks** → Remove from Recent Decisions
- **Stale parked items** → Promote to Open Threads or remove

### Step 8: Update memory

Edit the Memory file:
- Add new items (concise, one line each)
- Remove resolved/stale items
- Update "Now" section if priorities shifted
- **Keep total under ~100 lines**

### Step 9: Procrastination Detection

Cross-reference Task Board Today section against last 3 daily notes.

If any task appears unchecked in 3+ consecutive daily notes:
1. Flag it neutrally: "[Task] has been on Today for [N] days."
2. Ask one open question: "What's blocking this one?"
3. Listen to response. Don't jump to solutions yet.
4. Common resistance patterns:
   - Unclear approach → help break it down or clarify
   - Dreading it → acknowledge, offer tiny first step or "rip the bandaid"
   - Missing capability → identify what needs learning
   - Not actually important → move to Later or delete
5. Only suggest tactics AFTER understanding the block.

**Do NOT default to:** "Try Pomodoro" or "Just start with 10 minutes"

This step should take <1 minute. Flag and ask, then move on.

### Step 10: Report

Tell the user:
- Scratchpad items processed (if any)
- Meetings processed (if any)
- What was added to memory
- What was removed/pruned
- Current state of memory (brief summary)

---

## Memory Maintenance Rules

- Each bullet point should be ONE concise line
- Use format: `- Topic: status/context` for Open Threads
- Use format: `- [MMDDYY] Decision: rationale` for Recent Decisions
- If a section is empty, leave just `-` as placeholder
- Aggressively prune - memory is for ACTIVE context, not history
