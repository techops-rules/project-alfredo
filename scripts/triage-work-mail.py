#!/usr/bin/env python3
"""Triage work-mail-latest.md into actionable candidates vs FYI.

Rules-first (regex/domain match), no LLM. Writes candidates to
inbox/work-triage-YYYY-MM-DD.md for human-in-loop approval before
promoting to todos/work.md.
"""

import re
import sys
from datetime import datetime
from pathlib import Path

VAULT = Path.home() / "obsidian"
SOURCE = VAULT / "sources" / "work-mail-latest.md"
TODAY = datetime.now().strftime("%Y-%m-%d")
OUTPUT = VAULT / "inbox" / f"work-triage-{TODAY}.md"
TODOS_FILE = VAULT / "todos" / "work.md"

# --- Triage rules ---

# @-mention patterns — always escalate
MENTION_RE = re.compile(
    r"(?i)\b(?:@todd|todd\s*michel|todd,|hi\s+todd|hey\s+todd)\b"
)

# Action-word patterns in subject — likely needs response
ACTION_RE = re.compile(
    r"(?i)\b(?:action\s+required|please\s+review|approve|sign\s+off|"
    r"deadline|by\s+eod|urgent|asap|past\s+due|overdue|"
    r"assigned\s+to\s+you|needs?\s+your|waiting\s+on\s+you|"
    r"re:|fwd:)\b"
)

# Senders that are always FYI / noise (newsletters, marketing, system)
NOISE_DOMAINS = {
    "allegiant.com", "e.allegiant.com",
    "energybin.com",
    "email.freshworks.com",
    "go.infocastinc.com",
    "raptormaps.com",
    "marketing@raptormaps.com",
    "tigoenergy.com",
}

NOISE_SENDERS_RE = re.compile(
    r"(?i)(?:no-?reply|noreply|donotreply|notifications?@|"
    r"calendar-notification|mailer-daemon)"
)

# FYI categories — skip unless @-mentioned
FYI_SUBJECTS_RE = re.compile(
    r"(?i)(?:onboarding|vendor\s+registration|aravo|jll\s+supplier|"
    r"timecard\s+reminder|daily\s+agenda\s+for)"
)

# Deal Desk — extract one-liner, don't create todo
DEAL_DESK_RE = re.compile(r"(?i)deal\s+desk|new\s+signed?\s+deal")

# Timecard past-due — escalate
TIMECARD_PASTDUE_RE = re.compile(r"(?i)timecard.*(?:past\s+due|overdue)")

# 1:1 / meeting reminders from Lattice — worth surfacing
LATTICE_RE = re.compile(r"(?i)you\s+have\s+a\s+1:1\s+with")


def parse_emails(text: str) -> list[dict]:
    """Parse the markdown email digest into structured records."""
    entries = []
    current = None

    for line in text.split("\n"):
        line = line.strip()
        if not line:
            continue

        if line.startswith("## "):
            if current:
                entries.append(current)
            current = {"subject": line[3:].strip(), "from": "", "date": "", "read": ""}
        elif current:
            if line.startswith("- **From:**"):
                current["from"] = line.split("**From:**")[1].strip()
            elif line.startswith("- **Date:**"):
                current["date"] = line.split("**Date:**")[1].strip()
            elif line.startswith("- **Read:**"):
                current["read"] = line.split("**Read:**")[1].strip().lower()

    if current:
        entries.append(current)

    return entries


def extract_domain(sender: str) -> str:
    """Pull domain from 'Name <email>' or plain email."""
    match = re.search(r"<([^>]+)>", sender)
    email = match.group(1) if match else sender
    parts = email.split("@")
    return parts[1].lower() if len(parts) == 2 else ""


def classify(entry: dict) -> tuple[str, str]:
    """Return (category, reason) for an email entry.

    Categories: ACTION, FYI, NOISE, DEAL
    """
    subj = entry["subject"]
    sender = entry["from"]
    domain = extract_domain(sender)
    is_system = NOISE_SENDERS_RE.search(sender) is not None
    is_noise_domain = domain in NOISE_DOMAINS

    # Noise domains — filter first (marketing, newsletters)
    if is_noise_domain:
        return "NOISE", f"noise domain ({domain})"

    # Lattice 1:1 reminders — useful even though sender is "notifications@"
    if LATTICE_RE.search(subj):
        return "ACTION", "1:1 reminder"

    # System senders (no-reply, notifications, calendar) — filter before @-mention
    # so automated emails containing Todd's name don't escalate
    if is_system:
        return "NOISE", "system/no-reply sender"

    # @-mention from a real person — always escalate
    if MENTION_RE.search(subj):
        return "ACTION", "@-mention in subject"

    # Timecard past-due escalation
    if TIMECARD_PASTDUE_RE.search(subj):
        return "ACTION", "timecard past-due"

    # Deal Desk
    if DEAL_DESK_RE.search(subj):
        return "DEAL", "deal desk alert"

    # FYI subjects (onboarding, vendor, timecard reminder)
    if FYI_SUBJECTS_RE.search(subj):
        return "FYI", "informational category"

    # Action words in subject
    if ACTION_RE.search(subj):
        return "ACTION", f"action keyword in subject"

    # Re: threads from real people (not noise) — likely needs attention
    if subj.lower().startswith("re:") and not NOISE_SENDERS_RE.search(sender):
        return "ACTION", "reply thread from real sender"

    # Default: FYI
    return "FYI", "no signal detected"


def load_existing_todos() -> set[str]:
    """Load first 40 chars of each existing todo for dedup."""
    if not TODOS_FILE.exists():
        return set()
    todos = set()
    for line in TODOS_FILE.read_text().split("\n"):
        line = line.strip()
        if line.startswith("- [ ]") or line.startswith("- [x]"):
            text = line[5:].strip()[:40].lower()
            todos.add(text)
    return todos


def fuzzy_match(text: str, existing: set[str]) -> bool:
    """Check if a candidate todo fuzzy-matches an existing one."""
    normalized = text[:40].lower()
    for existing_text in existing:
        if normalized == existing_text:
            return True
        # Simple overlap check
        if len(normalized) > 10 and normalized[:20] == existing_text[:20]:
            return True
    return False


def main():
    if not SOURCE.exists():
        print(f"No source file: {SOURCE}")
        sys.exit(1)

    text = SOURCE.read_text()
    # Handle \r remnants
    text = text.replace("\r\n", "\n").replace("\r", "\n")

    entries = parse_emails(text)
    if not entries:
        print("No emails parsed from source.")
        sys.exit(0)

    existing_todos = load_existing_todos()

    actions = []
    deals = []
    fyi = []
    noise = []

    for entry in entries:
        cat, reason = classify(entry)
        entry["_category"] = cat
        entry["_reason"] = reason

        if cat == "ACTION":
            actions.append(entry)
        elif cat == "DEAL":
            deals.append(entry)
        elif cat == "FYI":
            fyi.append(entry)
        else:
            noise.append(entry)

    # Build output
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)

    lines = [
        f"# Work Email Triage — {TODAY}",
        f"",
        f"Source: `sources/work-mail-latest.md`",
        f"Processed: {datetime.now().strftime('%Y-%m-%d %H:%M')}",
        f"Total: {len(entries)} emails → {len(actions)} action, {len(deals)} deal, {len(fyi)} FYI, {len(noise)} noise",
        f"",
        f"**Review below. Move approved items to `todos/work.md` or dismiss.**",
        f"",
    ]

    if actions:
        lines.append("## Candidate Todos")
        lines.append("")
        for e in actions:
            candidate_text = e["subject"]
            is_dupe = fuzzy_match(candidate_text, existing_todos)
            dupe_tag = " ⚠️ possible dupe" if is_dupe else ""
            lines.append(f"- [ ] {e['subject']}{dupe_tag}")
            lines.append(f"  - From: {e['from']}")
            lines.append(f"  - Why: {e['_reason']}")
            lines.append("")

    if deals:
        lines.append("## Deal Desk (awareness only)")
        lines.append("")
        for e in deals:
            lines.append(f"- [Deal Desk] {e['subject']}")
            lines.append(f"  - From: {e['from']}")
            lines.append("")

    if fyi:
        lines.append("## FYI (skipped)")
        lines.append("")
        for e in fyi:
            lines.append(f"- {e['subject']} — {e['_reason']}")
        lines.append("")

    if noise:
        lines.append("## Noise (filtered)")
        lines.append("")
        for e in noise:
            lines.append(f"- ~~{e['subject']}~~ — {e['_reason']}")
        lines.append("")

    output_text = "\n".join(lines)
    OUTPUT.write_text(output_text)

    print(f"Triage complete: {OUTPUT}")
    print(f"  {len(actions)} action | {len(deals)} deal | {len(fyi)} FYI | {len(noise)} noise")

    if actions:
        print("\nCandidate todos:")
        for e in actions:
            print(f"  → {e['subject']} ({e['_reason']})")


if __name__ == "__main__":
    main()
