"""Shared IMAP fetch logic for alfredo email pipeline.

Used by fetch-work-mail.py and fetch-personal-mail.py.
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
KEYCHAIN_SERVICE = "alfredo-imap"


def get_password(email_addr: str) -> str:
    result = subprocess.run(
        ["security", "find-generic-password", "-a", email_addr, "-s", KEYCHAIN_SERVICE, "-w"],
        capture_output=True, text=True,
    )
    if result.returncode != 0:
        print(f"Keychain lookup failed for {email_addr}: {result.stderr.strip()}", file=sys.stderr)
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


def fetch_and_write(
    email_addr: str,
    label: str,
    out_path: Path,
    archive_prefix: str,
    days: int = 1,
):
    """Connect via IMAP, fetch headers, write digest + archive."""
    password = get_password(email_addr)

    print(f"Connecting to imap.gmail.com as {email_addr}...")
    conn = imaplib.IMAP4_SSL("imap.gmail.com", 993)
    conn.login(email_addr, password)

    messages = fetch_messages(conn, days)
    conn.logout()

    print(f"Fetched {len(messages)} messages from last {days}d")

    out_path.parent.mkdir(parents=True, exist_ok=True)
    ts = datetime.now().strftime("%Y-%m-%d %H:%M")
    today = datetime.now().strftime("%Y-%m-%d")

    lines = [
        f"# {label} Digest — {ts}",
        f"Account: Gmail ({email_addr})",
        f"Window: last {days}d",
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

    out_path.write_text("\n".join(lines))

    archive = out_path.parent / f"{archive_prefix}-{today}.md"
    if archive.exists():
        with open(archive, "a") as f:
            f.write("\n---\n\n")
            f.write("\n".join(lines))
    else:
        archive.write_text("\n".join(lines))

    print(f"Wrote: {out_path}")
    print(f"Archived: {archive}")
    return len(messages)
