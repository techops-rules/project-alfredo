#!/usr/bin/env python3
"""Fetch personal Gmail (todd375@gmail.com) via IMAP.

Reads app password from macOS Keychain. Writes to
~/obsidian/sources/personal-mail-latest.md in the same format
as work-mail-latest.md for triage pipeline compatibility.
"""

import email
import email.header
import email.utils
import imaplib
import subprocess
import sys
from datetime import datetime, timedelta
from pathlib import Path

VAULT = Path.home() / "obsidian"
OUT = VAULT / "sources" / "personal-mail-latest.md"
ARCHIVE_DIR = VAULT / "sources"

IMAP_HOST = "imap.gmail.com"
IMAP_PORT = 993
EMAIL_ADDR = "todd375@gmail.com"
KEYCHAIN_SERVICE = "alfredo-imap"

DAYS_BACK = int(sys.argv[1]) if len(sys.argv) > 1 else 1


def get_password() -> str:
    result = subprocess.run(
        ["security", "find-generic-password", "-a", EMAIL_ADDR, "-s", KEYCHAIN_SERVICE, "-w"],
        capture_output=True, text=True,
    )
    if result.returncode != 0:
        print(f"Keychain lookup failed: {result.stderr.strip()}", file=sys.stderr)
        sys.exit(1)
    return result.stdout.strip()


def decode_header(raw: str) -> str:
    parts = email.header.decode_header(raw)
    decoded = []
    for part, charset in parts:
        if isinstance(part, bytes):
            decoded.append(part.decode(charset or "utf-8", errors="replace"))
        else:
            decoded.append(part)
    return "".join(decoded)


def fetch_messages(conn: imaplib.IMAP4_SSL, days: int) -> list[dict]:
    conn.select("INBOX", readonly=True)

    since = (datetime.now() - timedelta(days=days)).strftime("%d-%b-%Y")
    _, msg_ids = conn.search(None, f'(SINCE "{since}")')

    if not msg_ids[0]:
        return []

    ids = msg_ids[0].split()
    messages = []

    for mid in ids:
        _, data = conn.fetch(mid, "(RFC822.SIZE FLAGS BODY.PEEK[HEADER])")
        if not data or not data[0]:
            continue

        raw_header = data[0][1]
        msg = email.message_from_bytes(raw_header)

        subject = decode_header(msg.get("Subject", "(no subject)"))
        from_raw = msg.get("From", "")
        from_decoded = decode_header(from_raw)
        date_str = msg.get("Date", "")
        parsed_date = email.utils.parsedate_to_datetime(date_str) if date_str else None
        date_display = parsed_date.strftime("%A, %B %d, %Y at %-I:%M:%S %p") if parsed_date else date_str

        flags = data[0][0].decode() if isinstance(data[0][0], bytes) else str(data[0][0])
        is_read = "\\Seen" in flags

        messages.append({
            "subject": subject,
            "from": from_decoded,
            "date": date_display,
            "read": str(is_read).lower(),
        })

    return messages


def main():
    password = get_password()

    print(f"Connecting to {IMAP_HOST}...")
    conn = imaplib.IMAP4_SSL(IMAP_HOST, IMAP_PORT)
    conn.login(EMAIL_ADDR, password)

    messages = fetch_messages(conn, DAYS_BACK)
    conn.logout()

    print(f"Fetched {len(messages)} messages from last {DAYS_BACK}d")

    ARCHIVE_DIR.mkdir(parents=True, exist_ok=True)
    ts = datetime.now().strftime("%Y-%m-%d %H:%M")
    today = datetime.now().strftime("%Y-%m-%d")

    lines = [
        f"# Personal Mail Digest — {ts}",
        f"Account: Gmail ({EMAIL_ADDR})",
        f"Window: last {DAYS_BACK}d",
        f"Source: IMAP direct",
        "",
        "---",
        "",
    ]

    for m in messages:
        lines.append(f"## {m['subject']}")
        lines.append(f"- **From:** {m['from']}")
        lines.append(f"- **Date:** {m['date']}")
        lines.append(f"- **Read:** {m['read']}")
        lines.append("")

    OUT.write_text("\n".join(lines))

    archive = ARCHIVE_DIR / f"personal-mail-{today}.md"
    if archive.exists():
        with open(archive, "a") as f:
            f.write("\n---\n\n")
            f.write("\n".join(lines))
    else:
        archive.write_text("\n".join(lines))

    print(f"Wrote: {OUT}")
    print(f"Archived: {archive}")


if __name__ == "__main__":
    main()
