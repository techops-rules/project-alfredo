#!/usr/bin/env bash
# Pull alfredo crash logs from macOS diagnostic reports and device logs
# Run manually or via scheduled task

CRASH_DIR="$(dirname "$0")"
REPORTS_DIR="$HOME/Library/Logs/DiagnosticReports"
LATEST="$CRASH_DIR/.last_pull"

echo "=== Alfredo Crash Log Pull — $(date) ==="

# Track what we've already pulled
touch "$LATEST" 2>/dev/null

count=0
for f in "$REPORTS_DIR"/alfredo-*.ips; do
    [ -f "$f" ] || continue
    base=$(basename "$f")
    dest="$CRASH_DIR/$base"
    if [ ! -f "$dest" ]; then
        cp "$f" "$dest"
        echo "NEW: $base"
        count=$((count + 1))
    fi
done

# Also check for .crash files
for f in "$REPORTS_DIR"/alfredo-*.crash; do
    [ -f "$f" ] || continue
    base=$(basename "$f")
    dest="$CRASH_DIR/$base"
    if [ ! -f "$dest" ]; then
        cp "$f" "$dest"
        echo "NEW: $base"
        count=$((count + 1))
    fi
done

if [ $count -eq 0 ]; then
    echo "No new crash logs found."
else
    echo "$count new crash log(s) pulled."

    # Extract key info from new crashes
    for f in "$CRASH_DIR"/alfredo-*.ips "$CRASH_DIR"/alfredo-*.crash; do
        [ -f "$f" ] || continue
        base=$(basename "$f")
        summary="$CRASH_DIR/${base%.*}.summary.txt"
        if [ ! -f "$summary" ]; then
            echo "--- $base ---" > "$summary"
            # Extract exception type and crashed thread backtrace
            grep -A2 "Exception Type\|Termination Reason\|Application Specific\|Fatal error" "$f" >> "$summary" 2>/dev/null
            echo "" >> "$summary"
            # Get the crashing thread's first 20 frames
            awk '/^Thread [0-9]+ Crashed/,/^$/' "$f" | head -25 >> "$summary" 2>/dev/null
            echo "Summary: $summary"
        fi
    done
fi

echo "=== Done ==="
