#!/bin/bash
# Bi-directional sync between ~/obsidian/todos/ and Pi kiosk vault_state.
# Runs every 30s via LaunchAgent.
set -uo pipefail

SCRIPTS="/Users/todd/Projects/project alfredo/scripts"
PI_URL="http://pihub.local:8430/proxy/vault-sync"
LOG="$HOME/Library/Logs/alfredo-kiosk-sync.log"
MAX_LOG_LINES=500

ts() { date "+%Y-%m-%d %H:%M:%S"; }

# Trim log if it gets huge
if [ -f "$LOG" ] && [ "$(wc -l < "$LOG")" -gt "$MAX_LOG_LINES" ]; then
    tail -n "$MAX_LOG_LINES" "$LOG" > "$LOG.tmp" && mv "$LOG.tmp" "$LOG"
fi

# Check Pi reachable
if ! ping -c 1 -W 2000 pihub.local > /dev/null 2>&1; then
    echo "$(ts) pi unreachable, skipped" >> "$LOG"
    exit 0
fi

# Build payload from local markdown
body=$("$SCRIPTS/obsidian-todos-to-json.py") || { echo "$(ts) parse FAILED" >> "$LOG"; exit 1; }

# POST to Pi
resp=$(curl -sS -m 10 -X POST -H "Content-Type: application/json" --data "$body" "$PI_URL") \
    || { echo "$(ts) POST FAILED: $resp" >> "$LOG"; exit 1; }

# Check if kiosk had edits; if so write them back to markdown
kiosk_has_edits=$(echo "$resp" | python3 -c "import json,sys;print(str(json.load(sys.stdin).get('kiosk_has_edits', False)).lower())" 2>/dev/null)

if [ "$kiosk_has_edits" = "true" ]; then
    changes=$(echo "$resp" | "$SCRIPTS/write-back-todos.py")
    change_count=$(echo "$changes" | python3 -c "import json,sys;d=json.load(sys.stdin);print(sum(len(v) for v in d.get('changes',{}).values()))" 2>/dev/null || echo 0)
    if [ "$change_count" -gt 0 ]; then
        echo "$(ts) write-back applied: $change_count change(s)" >> "$LOG"
    fi
else
    echo "$(ts) mac->pi synced ok" >> "$LOG"
fi
