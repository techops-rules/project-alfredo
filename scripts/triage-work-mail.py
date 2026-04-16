#!/usr/bin/env python3
"""Triage work-mail-latest.md into actionable candidates vs FYI.

Rules-first (regex/domain match), no LLM. Writes candidates to
inbox/work-triage-YYYY-MM-DD.md for human-in-loop approval before
promoting to todos/work.md.
"""

import re
import sys

from mail_common import (
    VAULT, TODAY,
    parse_emails, extract_domain, load_existing_todos,
    fuzzy_match, bucket_entries, write_triage_report,
)

SOURCE = VAULT / "sources" / "work-mail-latest.md"
OUTPUT = VAULT / "inbox" / f"work-triage-{TODAY}.md"
TODOS_FILE = VAULT / "todos" / "work.md"

# --- Triage rules ---

MENTION_RE = re.compile(
    r"(?i)\b(?:@todd|todd\s*michel|todd,|hi\s+todd|hey\s+todd)\b"
)

ACTION_RE = re.compile(
    r"(?i)\b(?:action\s+required|please\s+review|approve|sign\s+off|"
    r"deadline|by\s+eod|urgent|asap|past\s+due|overdue|"
    r"assigned\s+to\s+you|needs?\s+your|waiting\s+on\s+you|"
    r"re:|fwd:)\b"
)

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

FYI_SUBJECTS_RE = re.compile(
    r"(?i)(?:onboarding|vendor\s+registration|aravo|jll\s+supplier|"
    r"timecard\s+reminder|daily\s+agenda\s+for)"
)

DEAL_DESK_RE = re.compile(r"(?i)deal\s+desk|new\s+signed?\s+deal")
TIMECARD_PASTDUE_RE = re.compile(r"(?i)timecard.*(?:past\s+due|overdue)")
LATTICE_RE = re.compile(r"(?i)you\s+have\s+a\s+1:1\s+with")


def classify(entry: dict) -> tuple[str, str]:
    subj = entry["subject"]
    sender = entry["from"]
    domain = extract_domain(sender)
    is_system = NOISE_SENDERS_RE.search(sender) is not None

    if domain in NOISE_DOMAINS:
        return "NOISE", f"noise domain ({domain})"

    if LATTICE_RE.search(subj):
        return "ACTION", "1:1 reminder"

    if is_system:
        return "NOISE", "system/no-reply sender"

    if MENTION_RE.search(subj):
        return "ACTION", "@-mention in subject"

    if TIMECARD_PASTDUE_RE.search(subj):
        return "ACTION", "timecard past-due"

    if DEAL_DESK_RE.search(subj):
        return "DEAL", "deal desk alert"

    if FYI_SUBJECTS_RE.search(subj):
        return "FYI", "informational category"

    if ACTION_RE.search(subj):
        return "ACTION", "action keyword in subject"

    if subj.lower().startswith("re:") and not NOISE_SENDERS_RE.search(sender):
        return "ACTION", "reply thread from real sender"

    return "FYI", "no signal detected"


def main():
    if not SOURCE.exists():
        print(f"No source file: {SOURCE}")
        sys.exit(1)

    text = SOURCE.read_text()
    entries = parse_emails(text)
    if not entries:
        print("No emails parsed from source.")
        sys.exit(0)

    buckets = bucket_entries(entries, classify)
    actions = buckets.get("ACTION", [])
    deals = buckets.get("DEAL", [])
    fyi = buckets.get("FYI", [])
    noise = buckets.get("NOISE", [])

    existing_todos = load_existing_todos(TODOS_FILE)
    for e in actions:
        e["_is_dupe"] = fuzzy_match(e["subject"], existing_todos)

    write_triage_report(
        output_path=OUTPUT,
        title="Work Email Triage",
        source_label="sources/work-mail-latest.md",
        total=len(entries),
        header_note="Review below. Move approved items to `todos/work.md` or dismiss.",
        sections=[
            {"heading": "Candidate Todos", "entries": actions, "label": "action",
             "style": "checkbox", "show_dupe": True},
            {"heading": "Deal Desk (awareness only)", "entries": deals, "label": "deal",
             "style": "deal"},
            {"heading": "FYI (skipped)", "entries": fyi, "label": "FYI",
             "style": "plain", "show_reason": True},
            {"heading": "Noise (filtered)", "entries": noise, "label": "noise",
             "style": "strikethrough"},
        ],
    )

    print(f"Triage complete: {OUTPUT}")
    print(f"  {len(actions)} action | {len(deals)} deal | {len(fyi)} FYI | {len(noise)} noise")

    if actions:
        print("\nCandidate todos:")
        for e in actions:
            print(f"  → {e['subject']} ({e['_reason']})")


if __name__ == "__main__":
    main()
