"""Shared utilities for the alfredo email triage pipeline.

Used by triage-work-mail.py and triage-personal-mail.py.
"""

import re
from datetime import datetime
from pathlib import Path

VAULT = Path.home() / "obsidian"
TODAY = datetime.now().strftime("%Y-%m-%d")
NOW = datetime.now().strftime("%Y-%m-%d %H:%M")


def parse_emails(text: str) -> list[dict]:
    """Parse a markdown email digest into structured records."""
    text = text.replace("\r\n", "\n").replace("\r", "\n")
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
    addr = match.group(1) if match else sender
    parts = addr.split("@")
    return parts[1].lower() if len(parts) == 2 else ""


def load_existing_todos(path: Path) -> set[str]:
    """Load first 40 chars of each existing todo for dedup."""
    if not path.exists():
        return set()
    todos = set()
    for line in path.read_text().split("\n"):
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
        if len(normalized) > 10 and normalized[:20] == existing_text[:20]:
            return True
    return False


def bucket_entries(entries: list[dict], classify_fn) -> dict[str, list[dict]]:
    """Classify entries and group by category."""
    buckets: dict[str, list[dict]] = {}
    for entry in entries:
        cat, reason = classify_fn(entry)
        entry["_category"] = cat
        entry["_reason"] = reason
        buckets.setdefault(cat, []).append(entry)
    return buckets


def write_triage_report(
    output_path: Path,
    title: str,
    source_label: str,
    total: int,
    sections: list[dict],
    header_note: str = "",
):
    """Write a structured triage markdown report.

    Each section dict: {
        "heading": str,
        "entries": list[dict],
        "style": "checkbox" | "plain" | "strikethrough" | "count_only",
        "show_from": bool (default True for checkbox),
        "show_reason": bool (default True for checkbox),
    }
    """
    counts = " → ".join(f"{s.get('count', len(s['entries']))} {s['label']}" for s in sections)

    lines = [
        f"# {title} — {TODAY}",
        "",
        f"Source: `{source_label}`",
        f"Processed: {NOW}",
        f"Total: {total} emails → {counts}",
        "",
    ]

    if header_note:
        lines.append(f"**{header_note}**")
        lines.append("")

    for section in sections:
        entries = section["entries"]
        if not entries:
            continue

        style = section.get("style", "plain")
        heading = section["heading"]
        lines.append(f"## {heading}")
        lines.append("")

        if style == "count_only":
            lines.append(f"_{len(entries)} {section.get('summary', 'items filtered')}._")
            lines.append("")
            continue

        for e in entries:
            if style == "checkbox":
                suffix = ""
                if section.get("show_dupe") and e.get("_is_dupe"):
                    suffix = " ⚠️ possible dupe"
                lines.append(f"- [ ] {e['subject']}{suffix}")
                if section.get("show_from", True):
                    lines.append(f"  - From: {e['from']}")
                if section.get("show_reason", True):
                    lines.append(f"  - Why: {e['_reason']}")
                lines.append("")
            elif style == "strikethrough":
                lines.append(f"- ~~{e['subject']}~~ — {e['_reason']}")
            elif style == "deal":
                lines.append(f"- [Deal Desk] {e['subject']}")
                lines.append(f"  - From: {e['from']}")
                lines.append("")
            else:
                lines.append(f"- {e['subject']}" + (f" — {e['_reason']}" if section.get("show_reason") else ""))

        if style not in ("checkbox", "deal"):
            lines.append("")

    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text("\n".join(lines))
    return output_path
