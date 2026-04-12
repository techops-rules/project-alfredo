#!/usr/bin/env bash
set -euo pipefail

# ═══════════════════════════════════════════════════════════════
#  ALFREDO LOCAL RECOVERY — runs ON the Pi from /boot/alfredo-recovery/
#  Triggered by alfredo-self-heal.sh L4 (nuclear option)
#  Also runnable manually: bash /boot/alfredo-recovery/recover-local.sh
# ═══════════════════════════════════════════════════════════════

RECOVERY_DIR="/boot/alfredo-recovery"
HOME_DIR="/home/todd"
KIOSK_DIR="$HOME_DIR/alfredo-kiosk"
ISSUES_DIR="$KIOSK_DIR/issues"
LOG="/var/log/alfredo-rebuild.log"
LOG_TAG="alfredo-rebuild"
FAILED=()

log() { logger -t "$LOG_TAG" "$*"; echo "$(date +%H:%M:%S) $*" | tee -a "$LOG"; }

try_step() {
    local label="$1"
    shift
    log "STEP: $label"
    if "$@" >> "$LOG" 2>&1; then
        log "  OK: $label"
        return 0
    else
        log "  FAIL: $label"
        FAILED+=("$label")
        return 1
    fi
}

log "═══ ALFREDO LOCAL REBUILD STARTED ═══"
espeak-ng "Beginning local system rebuild." 2>/dev/null || true

# ── 1. Directories ───────────────────────────────────────
try_step "Create directories" bash -c "
mkdir -p '$KIOSK_DIR' '$KIOSK_DIR/issues' '$HOME_DIR/alfredo-bridge' '$HOME_DIR/.config/labwc' '$HOME_DIR/piper-voices'
" || true

# ── 2. Restore files from recovery partition ─────────────
log "Restoring files from $RECOVERY_DIR"

# Kiosk files
if [ -d "$RECOVERY_DIR/kiosk" ]; then
    for f in "$RECOVERY_DIR/kiosk/"*; do
        [ -f "$f" ] || continue
        fname=$(basename "$f")
        try_step "Restore kiosk/$fname" cp -f "$f" "$KIOSK_DIR/$fname" || true
    done
fi

# Bridge files
if [ -d "$RECOVERY_DIR/bridge" ]; then
    [ -f "$RECOVERY_DIR/bridge/alfredo-bridge.py" ] && \
        try_step "Restore alfredo-bridge.py" cp -f "$RECOVERY_DIR/bridge/alfredo-bridge.py" "$HOME_DIR/alfredo-bridge.py" || true
    [ -f "$RECOVERY_DIR/bridge/alfredo-watchdog.sh" ] && \
        try_step "Restore watchdog" cp -f "$RECOVERY_DIR/bridge/alfredo-watchdog.sh" "$HOME_DIR/alfredo-bridge/alfredo-watchdog.sh" || true
    [ -f "$RECOVERY_DIR/bridge/alfredo-self-heal.sh" ] && \
        try_step "Restore self-heal" cp -f "$RECOVERY_DIR/bridge/alfredo-self-heal.sh" "$HOME_DIR/alfredo-bridge/alfredo-self-heal.sh" || true
fi

# Config files (preserve user customizations for presence.json)
if [ -d "$RECOVERY_DIR/config" ]; then
    [ -f "$RECOVERY_DIR/config/persona.md" ] && \
        try_step "Restore persona" cp -f "$RECOVERY_DIR/config/persona.md" "$KIOSK_DIR/persona.md" || true
    [ -f "$RECOVERY_DIR/config/calendar-feeds.json" ] && \
        try_step "Restore calendar feeds" cp -f "$RECOVERY_DIR/config/calendar-feeds.json" "$KIOSK_DIR/calendar-feeds.json" || true
    [ ! -f "$KIOSK_DIR/presence.json" ] && [ -f "$RECOVERY_DIR/config/presence.json" ] && \
        try_step "Restore presence config" cp -f "$RECOVERY_DIR/config/presence.json" "$KIOSK_DIR/presence.json" || true
fi

# Autostart
[ -f "$RECOVERY_DIR/labwc-autostart" ] && \
    try_step "Restore autostart" cp -f "$RECOVERY_DIR/labwc-autostart" "$HOME_DIR/.config/labwc/autostart" || true

# ── 3. Systemd services ─────────────────────────────────
log "Restoring systemd services"
if [ -d "$RECOVERY_DIR/services" ]; then
    for svc in "$RECOVERY_DIR/services/"*.service "$RECOVERY_DIR/services/"*.timer; do
        [ -f "$svc" ] || continue
        try_step "Install $(basename "$svc")" sudo cp -f "$svc" /etc/systemd/system/ || true
    done
    try_step "daemon-reload" sudo systemctl daemon-reload || true
fi

# ── 4. Permissions ───────────────────────────────────────
try_step "Permissions" bash -c "
chmod +x '$HOME_DIR/alfredo-bridge.py' 2>/dev/null
chmod +x '$HOME_DIR/alfredo-bridge/alfredo-watchdog.sh' 2>/dev/null
chmod +x '$HOME_DIR/alfredo-bridge/alfredo-self-heal.sh' 2>/dev/null
chmod +x '$HOME_DIR/.config/labwc/autostart' 2>/dev/null
chown -R todd:todd '$KIOSK_DIR' '$HOME_DIR/alfredo-bridge' 2>/dev/null
" || true

# ── 5. Python venv ───────────────────────────────────────
if [ ! -d "$HOME_DIR/alfredo-venv/bin" ] || ! "$HOME_DIR/alfredo-venv/bin/python3" -c "import websockets" 2>/dev/null; then
    try_step "Rebuild Python venv" bash -c "
rm -rf '$HOME_DIR/alfredo-venv'
python3 -m venv '$HOME_DIR/alfredo-venv'
'$HOME_DIR/alfredo-venv/bin/pip' install --quiet websockets
" || true
else
    log "  Python venv OK"
fi

# ── 6. Fix broken apt if needed ──────────────────────────
try_step "Fix apt state" bash -c "
sudo dpkg --configure -a 2>/dev/null
sudo apt-get -f install -y -qq 2>/dev/null
" || true

# ── 7. Enable and start services ────────────────────────
try_step "Enable services" bash -c "
sudo systemctl enable alfredo-bridge alfredo-kiosk-web alfredo-watchdog.timer alfredo-wake alfredo-self-heal.timer 2>/dev/null
" || true

log "Starting services"
try_step "Start kiosk-web" sudo systemctl restart alfredo-kiosk-web || true
sleep 2
try_step "Start bridge" sudo systemctl restart alfredo-bridge || true
try_step "Start watchdog" sudo systemctl restart alfredo-watchdog.timer || true
try_step "Start self-heal" sudo systemctl restart alfredo-self-heal.timer || true
try_step "Start wake" sudo systemctl restart alfredo-wake || true

# ── 8. Retry failures ───────────────────────────────────
if [ ${#FAILED[@]} -gt 0 ]; then
    log "RETRY: ${#FAILED[@]} steps failed, retrying..."
    sleep 3
    STILL_FAILED=()
    for step in "${FAILED[@]}"; do
        case "$step" in
            "Start "*)
                svc_name=$(echo "$step" | sed 's/Start /alfredo-/')
                if sudo systemctl restart "$svc_name" 2>/dev/null; then
                    log "  RETRY OK: $step"
                else
                    STILL_FAILED+=("$step")
                fi
                ;;
            *)
                STILL_FAILED+=("$step")
                ;;
        esac
    done
    FAILED=("${STILL_FAILED[@]}")
fi

# ── 9. Log unresolved issues ────────────────────────────
if [ ${#FAILED[@]} -gt 0 ]; then
    log "UNRESOLVED: ${#FAILED[@]} steps still failing"
    mkdir -p "$ISSUES_DIR"
    ts=$(date +%Y%m%d-%H%M%S)
    cat > "$ISSUES_DIR/${ts}-rebuild-partial.md" <<EOF
---
component: local-rebuild
status: open
created: $(date -Iseconds)
auto-heal: partial
---

# [heal-todo] Partial rebuild — ${#FAILED[@]} steps failed

**Failed steps:**
$(for s in "${FAILED[@]}"; do echo "- $s"; done)

**Rebuild log:** /var/log/alfredo-rebuild.log
**System:** $(uname -a)
**Disk:** $(df -h / | tail -1)
EOF

    # Commit issue to git
    if [ -d "$KIOSK_DIR/.git" ]; then
        (cd "$KIOSK_DIR" && git add issues/ && git commit -q -m "[heal-todo] Partial rebuild: ${#FAILED[@]} steps failed" 2>/dev/null || true)
    fi
fi

# ── 10. Verify ──────────────────────────────────────────
sleep 3
HEALTHY=true
curl -sf --max-time 5 http://localhost:8430/ >/dev/null 2>&1 || HEALTHY=false

if $HEALTHY; then
    log "═══ REBUILD SUCCESSFUL ═══"
    espeak-ng "Rebuild complete. All systems restored. Try not to break me again." 2>/dev/null || true
else
    log "═══ REBUILD DONE — ${#FAILED[@]} issues remain ═══"
    espeak-ng "Rebuild complete. ${#FAILED[@]} issues need attention." 2>/dev/null || true
fi

# Clear heal state
echo "TARGETED_FIXES=0
BROAD_RESTARTS=0
REBOOT_COUNT=0
LAST_GOOD=$(date +%s)" > /tmp/alfredo-heal-state

exit 0
