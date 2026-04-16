#!/bin/bash
# Tax day nudge — iMessage ping every 2h on 2026-04-15 starting 2pm.
# Auto-silences once the "TAXES" line in personal.md is unchecked → checked.
set -uo pipefail

TODO="$HOME/obsidian/todos/personal.md"
PHONE="+16107453879"
TODAY=$(date +%Y-%m-%d)
HOUR=$(date +%H)

# Only fire on 2026-04-15
[ "$TODAY" != "2026-04-15" ] && exit 0

# Only fire between 14:00 and 22:00
[ "$HOUR" -lt 14 ] && exit 0
[ "$HOUR" -ge 23 ] && exit 0

# If taxes already checked off, silence
if grep -q "^- \[x\].*TAXES" "$TODO" 2>/dev/null; then
    exit 0
fi

# Build the message (escalating tone)
case "$HOUR" in
    14|15) MSG="reminder: taxes due tonight 11:59pm. still unchecked." ;;
    16|17) MSG="taxes. 11:59pm deadline. dont make me yell." ;;
    18|19) MSG="TAXES. file them. 11:59pm cutoff." ;;
    20|21|22) MSG="TAXES. seriously. minutes left. GO." ;;
    *) MSG="taxes today. go." ;;
esac

osascript <<APPLESCRIPT
tell application "Messages"
    set targetService to 1st service whose service type = iMessage
    set targetBuddy to buddy "$PHONE" of targetService
    send "$MSG" to targetBuddy
end tell
APPLESCRIPT

echo "$(date '+%Y-%m-%d %H:%M:%S') sent: $MSG" >> "$HOME/Library/Logs/alfredo-tax-nudge.log"
