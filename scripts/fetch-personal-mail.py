#!/usr/bin/env python3
"""Fetch personal Gmail (todd375@gmail.com) via IMAP.

Reads app password from macOS Keychain. Writes to
~/obsidian/sources/personal-mail-latest.md for triage pipeline.
"""

import sys
from pathlib import Path
from imap_fetch import VAULT, fetch_and_write

DAYS_BACK = int(sys.argv[1]) if len(sys.argv) > 1 else 1

fetch_and_write(
    email_addr="todd375@gmail.com",
    label="Personal Mail",
    out_path=VAULT / "sources" / "personal-mail-latest.md",
    archive_prefix="personal-mail",
    days=DAYS_BACK,
)
