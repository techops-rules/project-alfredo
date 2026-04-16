#!/usr/bin/env python3
"""Fetch work Gmail (tmichel@omnidian.com) via IMAP.

Reads app password from macOS Keychain. Writes to
~/obsidian/sources/work-mail-latest.md for triage pipeline.
"""

import sys
from pathlib import Path
from imap_fetch import VAULT, fetch_and_write

DAYS_BACK = int(sys.argv[1]) if len(sys.argv) > 1 else 1

fetch_and_write(
    email_addr="tmichel@omnidian.com",
    label="Work Mail",
    out_path=VAULT / "sources" / "work-mail-latest.md",
    archive_prefix="work-mail",
    days=DAYS_BACK,
)
