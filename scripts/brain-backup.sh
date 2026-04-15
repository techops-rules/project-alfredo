#!/bin/bash
# Redundant backup of Obsidian external brain vault.
# Four copies: local (~/obsidian) → GitHub → iCloud Drive mirror → pihub.local mirror.
# Run nightly via ~/Library/LaunchAgents/com.alfredo.brain-backup.plist.
set -uo pipefail

VAULT="$HOME/obsidian"
ICLOUD_MIRROR="$HOME/Library/Mobile Documents/com~apple~CloudDocs/obsidian-backup"
PI_HOST="pihub.local"
PI_MIRROR="/home/todd/obsidian-mirror"
LOG="$HOME/Library/Logs/alfredo-brain-backup.log"
TS=$(date "+%Y-%m-%d %H:%M:%S")

echo "=== $TS ===" >> "$LOG"

# 1. Commit + push to GitHub
cd "$VAULT" || exit 1
if [ -n "$(git status --porcelain)" ]; then
    git add -A
    git commit -m "auto: brain backup $TS" >> "$LOG" 2>&1
    git push origin main >> "$LOG" 2>&1 && echo "github: pushed" >> "$LOG" || echo "github: push FAILED" >> "$LOG"
else
    echo "github: no changes" >> "$LOG"
fi

# 2. rsync to iCloud Drive mirror (read-only, Obsidian never opens this)
mkdir -p "$ICLOUD_MIRROR"
rsync -a --delete --exclude='.obsidian/workspace.json' --exclude='.DS_Store' \
    "$VAULT/" "$ICLOUD_MIRROR/" >> "$LOG" 2>&1 \
    && echo "icloud: synced" >> "$LOG" \
    || echo "icloud: sync FAILED" >> "$LOG"

# 3. rsync to Pi mirror (read-only backup)
if ping -c 1 -W 2000 "$PI_HOST" > /dev/null 2>&1; then
    rsync -a --delete --exclude='.obsidian/workspace.json' --exclude='.DS_Store' \
        -e "ssh -o ConnectTimeout=5" \
        "$VAULT/" "${PI_HOST}:${PI_MIRROR}/" >> "$LOG" 2>&1 \
        && echo "pi: synced" >> "$LOG" \
        || echo "pi: sync FAILED" >> "$LOG"
else
    echo "pi: unreachable, skipped" >> "$LOG"
fi

echo "" >> "$LOG"
