#!/bin/bash
set -euo pipefail

DAYS_BACK="${1:-1}"
VAULT="$HOME/obsidian"
OUT="$VAULT/sources/work-mail-latest.md"
ARCHIVE="$VAULT/sources/work-mail-$(date +%Y-%m-%d).md"

mkdir -p "$VAULT/sources"
TS=$(date "+%Y-%m-%d %H:%M")

cat > "$OUT" <<EOF
# Work Mail Digest — $TS
Account: Google (tmichel@omnidian.com)
Window: last ${DAYS_BACK}d
Source: Apple Mail via AppleScript (read-only)

---

EOF

TMPRAW=$(mktemp)
osascript <<'APPLESCRIPT' > "$TMPRAW" 2>/dev/null || echo "_(AppleScript failed — check System Settings → Privacy & Security → Automation → Terminal → Mail)_" > "$TMPRAW"
tell application "Mail"
    set cutoff to (current date) - (1 * days)
    set acct to account "Google"
    set inboxMailbox to mailbox "INBOX" of acct
    set msgs to (messages of inboxMailbox whose date received > cutoff)
    set output to ""
    repeat with m in msgs
        try
            set subj to subject of m
            set snd to sender of m
            set recvDate to date received of m
            set readFlag to read status of m
            set output to output & "## " & subj & return
            set output to output & "- **From:** " & snd & return
            set output to output & "- **Date:** " & (recvDate as string) & return
            set output to output & "- **Read:** " & readFlag & return
            set output to output & return
        end try
    end repeat
    return output
end tell
APPLESCRIPT

# AppleScript `return` emits \r — normalize to \n
tr '\r' '\n' < "$TMPRAW" >> "$OUT"
rm -f "$TMPRAW"

# Archive: append to dated file (don't overwrite earlier runs)
if [ -f "$ARCHIVE" ]; then
    printf '\n---\n\n' >> "$ARCHIVE"
fi
cat "$OUT" >> "$ARCHIVE"
echo "wrote: $OUT"
echo "archived: $ARCHIVE"