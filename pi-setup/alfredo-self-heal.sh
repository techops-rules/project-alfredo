#!/usr/bin/env bash
set -euo pipefail

# ════���══════════════════════════════════════════════════════════
#  ALFREDO SELF-HEAL — surgical repair → reboot → rebuild
#
#  Every 5 min via alfredo-self-heal.timer.
#  Escalation:
#    L1: Diagnose which specific service/component is broken, fix just that
#    L2: Restart all services (3 attempts)
#    L3: Reboot (2 attempts)
#    L4: Full rebuild from recovery partition
#
#  Issues that can't be auto-fixed get logged to ~/alfredo-kiosk/issues/
#  and committed to git with [heal-todo] tag for Claude/Codex to pick up.
# ═════��═══════════════════════════���═════════════════════════════

LOG_TAG="alfredo-heal"
STATE_FILE="/tmp/alfredo-heal-state"
RECOVERY_DIR="/boot/alfredo-recovery"
KIOSK_DIR="$HOME/alfredo-kiosk"
ISSUES_DIR="$HOME/alfredo-kiosk/issues"
BRIDGE_DIR="$HOME/alfredo-bridge"
HEALTH_TIMEOUT=8
MAX_TARGETED_FIXES=6    # try targeted fixes this many times before broad restart
MAX_BROAD_RESTARTS=3    # broad restart before reboot
MAX_REBOOTS=2           # reboots before full rebuild

log() { logger -t "$LOG_TAG" "$*"; echo "$(date +%H:%M:%S) $*"; }

# ── Read state ───────��────────────────────────────────────
TARGETED_FIXES=0
BROAD_RESTARTS=0
REBOOT_COUNT=0
LAST_GOOD=0

if [ -f "$STATE_FILE" ]; then
    source "$STATE_FILE" 2>/dev/null || true
fi

save_state() {
    cat > "$STATE_FILE" <<EOF
TARGETED_FIXES=$TARGETED_FIXES
BROAD_RESTARTS=$BROAD_RESTARTS
REBOOT_COUNT=$REBOOT_COUNT
LAST_GOOD=$LAST_GOOD
EOF
}

# ── Issue logging (to git) ─────────���──────────────────────
log_issue() {
    local component="$1" summary="$2" detail="${3:-}"
    local ts=$(date +%Y%m%d-%H%M%S)
    local slug=$(echo "$component" | tr ' /' '-' | tr '[:upper:]' '[:lower:]')
    local issue_file="$ISSUES_DIR/${ts}-${slug}.md"

    mkdir -p "$ISSUES_DIR"

    cat > "$issue_file" <<EOF
---
component: $component
status: open
created: $(date -Iseconds)
auto-heal: failed
---

# [heal-todo] $summary

**Component:** $component
**Detected:** $(date)
**Auto-heal attempts:** targeted=$TARGETED_FIXES, restarts=$BROAD_RESTARTS, reboots=$REBOOT_COUNT

## Error detail
\`\`\`
$detail
\`\`\`

## Context
- Last healthy: $(date -d @$LAST_GOOD 2>/dev/null || date -r $LAST_GOOD 2>/dev/null || echo "unknown")
- System uptime: $(uptime 2>/dev/null || echo "unknown")
- Disk: $(df -h / 2>/dev/null | tail -1 || echo "unknown")
- Memory: $(free -h 2>/dev/null | grep Mem || echo "unknown")
EOF

    # Commit to git if repo exists
    if [ -d "$KIOSK_DIR/.git" ] || [ -d "$HOME/project-alfredo/.git" ]; then
        local git_dir="$KIOSK_DIR"
        [ -d "$HOME/project-alfredo/.git" ] && git_dir="$HOME/project-alfredo"
        (
            cd "$git_dir"
            git add "$issue_file" 2>/dev/null || true
            git commit -m "[heal-todo] $component: $summary

Auto-detected by alfredo-self-heal at $(date).
Targeted fixes exhausted. Needs human or agent review." 2>/dev/null || true
        )
        log "ISSUE: logged and committed: $issue_file"
    else
        log "ISSUE: logged (no git): $issue_file"
    fi
}

# ══════════════════════════════════════════════════════════
#  DIAGNOSTIC: check each component independently
# ══════════════════════════════════════════════════════════

declare -A BROKEN       # component → error detail
declare -A FIXED        # components we fixed this run

diagnose() {
    BROKEN=()

    # 1. Kiosk web server (serve.py on :8430)
    if ! curl -sf --max-time "$HEALTH_TIMEOUT" http://localhost:8430/ >/dev/null 2>&1; then
        if systemctl is-active alfredo-kiosk-web &>/dev/null; then
            # Service thinks it's running but HTTP is down
            local svc_log=$(journalctl -u alfredo-kiosk-web --no-pager -n 10 2>/dev/null || echo "no logs")
            BROKEN[kiosk-web]="service active but HTTP unresponsive|$svc_log"
        else
            local svc_log=$(journalctl -u alfredo-kiosk-web --no-pager -n 10 2>/dev/null || echo "no logs")
            BROKEN[kiosk-web]="service not running|$svc_log"
        fi
    fi

    # 2. serve.py process
    if ! pgrep -f "python.*serve.py" >/dev/null 2>&1; then
        if [ ! -f "$KIOSK_DIR/serve.py" ]; then
            BROKEN[serve-py]="serve.py file missing|ls: $(ls $KIOSK_DIR/ 2>/dev/null | head -5)"
        else
            local py_err=$(python3 -c "import py_compile; py_compile.compile('$KIOSK_DIR/serve.py', doraise=True)" 2>&1 || true)
            if [ -n "$py_err" ]; then
                BROKEN[serve-py]="syntax error in serve.py|$py_err"
            fi
        fi
    fi

    # 3. Chromium kiosk
    if ! pgrep -f "chromium.*kiosk" >/dev/null 2>&1; then
        # Only broken if web server is up (otherwise chromium can't load anything useful)
        if curl -sf --max-time 3 http://localhost:8430/ >/dev/null 2>&1; then
            BROKEN[chromium]="not running but web server is up"
        fi
    fi

    # 4. Bridge (optional but tracked)
    if ! curl -sf --max-time "$HEALTH_TIMEOUT" http://localhost:8420/health >/dev/null 2>&1; then
        if systemctl is-active alfredo-bridge &>/dev/null; then
            BROKEN[bridge]="service active but health check failed"
        elif ! command -v claude &>/dev/null && [ ! -f "$HOME/.local/bin/claude" ]; then
            # Bridge needs Claude CLI — not an auto-fixable issue, just note it
            : # skip, this is expected if Claude isn't installed yet
        else
            local svc_log=$(journalctl -u alfredo-bridge --no-pager -n 5 2>/dev/null || echo "")
            BROKEN[bridge]="service not running|$svc_log"
        fi
    fi

    # 5. Python venv
    if [ ! -d "$HOME/alfredo-venv/bin" ]; then
        BROKEN[python-venv]="venv missing or corrupt"
    elif ! "$HOME/alfredo-venv/bin/python3" -c "import websockets" 2>/dev/null; then
        BROKEN[python-venv]="websockets package missing from venv"
    fi

    # 6. Disk space
    local disk_pct=$(df / 2>/dev/null | tail -1 | awk '{print $5}' | tr -d '%')
    if [ "${disk_pct:-0}" -gt 95 ]; then
        BROKEN[disk]="root filesystem ${disk_pct}% full"
    fi

    # 7. Memory
    local mem_avail=$(awk '/MemAvailable/ {print int($2/1024)}' /proc/meminfo 2>/dev/null || echo "999")
    if [ "$mem_avail" -lt 50 ]; then
        BROKEN[memory]="only ${mem_avail}MB available"
    fi

    # 8. Key files exist
    for f in "$KIOSK_DIR/index.html" "$KIOSK_DIR/serve.py" "$HOME/alfredo-bridge.py"; do
        if [ ! -f "$f" ]; then
            BROKEN[missing-file]="$f does not exist"
        fi
    done
}

# ═══════════════════════���══════════════════════════════════
#  TARGETED FIXES: repair specific components
# ═════════��══════════════════��═════════════════════════════

try_fix() {
    local component="$1"
    local detail="${BROKEN[$component]}"
    log "FIX: attempting targeted fix for $component"

    case "$component" in
        kiosk-web)
            # Strategy 1: just restart the service
            sudo systemctl restart alfredo-kiosk-web 2>/dev/null
            sleep 3
            if curl -sf --max-time 5 http://localhost:8430/ >/dev/null 2>&1; then
                FIXED[$component]="service restart"
                return 0
            fi
            # Strategy 2: kill orphan python processes and restart
            pkill -f "python.*serve.py" 2>/dev/null || true
            sleep 1
            sudo systemctl restart alfredo-kiosk-web
            sleep 3
            if curl -sf --max-time 5 http://localhost:8430/ >/dev/null 2>&1; then
                FIXED[$component]="kill orphans + restart"
                return 0
            fi
            # Strategy 3: restore serve.py from recovery partition
            if [ -f "$RECOVERY_DIR/kiosk/serve.py" ]; then
                cp -f "$RECOVERY_DIR/kiosk/serve.py" "$KIOSK_DIR/serve.py"
                sudo systemctl restart alfredo-kiosk-web
                sleep 3
                if curl -sf --max-time 5 http://localhost:8430/ >/dev/null 2>&1; then
                    FIXED[$component]="restored from recovery"
                    return 0
                fi
            fi
            return 1
            ;;

        serve-py)
            # Restore from recovery
            if [ -f "$RECOVERY_DIR/kiosk/serve.py" ]; then
                cp -f "$RECOVERY_DIR/kiosk/serve.py" "$KIOSK_DIR/serve.py"
                sudo systemctl restart alfredo-kiosk-web
                sleep 2
                FIXED[$component]="restored from recovery"
                return 0
            fi
            return 1
            ;;

        chromium)
            export WAYLAND_DISPLAY=wayland-0
            export XDG_RUNTIME_DIR=/run/user/1000
            local url="http://localhost:8430/"
            [ -f "$KIOSK_DIR/boot-splash.html" ] && url="http://localhost:8430/boot-splash.html"
            chromium --kiosk --ozone-platform=wayland --noerrdialogs --no-first-run \
                --disable-infobars --disable-session-crashed-bubble \
                --start-fullscreen --autoplay-policy=no-user-gesture-required \
                "$url" &>/dev/null &
            sleep 3
            if pgrep -f "chromium.*kiosk" >/dev/null 2>&1; then
                FIXED[$component]="relaunched"
                return 0
            fi
            return 1
            ;;

        bridge)
            sudo systemctl restart alfredo-bridge 2>/dev/null
            sleep 3
            if curl -sf --max-time 5 http://localhost:8420/health >/dev/null 2>&1; then
                FIXED[$component]="service restart"
                return 0
            fi
            # Restore bridge.py from recovery
            if [ -f "$RECOVERY_DIR/bridge/alfredo-bridge.py" ]; then
                cp -f "$RECOVERY_DIR/bridge/alfredo-bridge.py" "$HOME/alfredo-bridge.py"
                sudo systemctl restart alfredo-bridge
                sleep 3
                if curl -sf --max-time 5 http://localhost:8420/health >/dev/null 2>&1; then
                    FIXED[$component]="restored from recovery"
                    return 0
                fi
            fi
            return 1
            ;;

        python-venv)
            # Rebuild venv
            rm -rf "$HOME/alfredo-venv"
            python3 -m venv "$HOME/alfredo-venv" 2>/dev/null
            "$HOME/alfredo-venv/bin/pip" install --quiet websockets 2>/dev/null
            if "$HOME/alfredo-venv/bin/python3" -c "import websockets" 2>/dev/null; then
                FIXED[$component]="rebuilt venv"
                sudo systemctl restart alfredo-bridge
                return 0
            fi
            return 1
            ;;

        disk)
            # Clean up what we can
            sudo apt-get autoremove -y -qq 2>/dev/null || true
            sudo apt-get clean 2>/dev/null || true
            sudo journalctl --vacuum-time=3d 2>/dev/null || true
            rm -rf /tmp/alfredo-recovery-*.log 2>/dev/null || true
            local after=$(df / | tail -1 | awk '{print $5}' | tr -d '%')
            if [ "$after" -lt 95 ]; then
                FIXED[$component]="freed space (now ${after}%)"
                return 0
            fi
            return 1
            ;;

        memory)
            # Kill known memory hogs, restart services
            pkill -f "chromium.*renderer" 2>/dev/null || true
            sleep 2
            sudo systemctl restart alfredo-kiosk-web alfredo-bridge 2>/dev/null || true
            FIXED[$component]="killed renderers + restarted"
            return 0
            ;;

        missing-file)
            # Restore from recovery partition
            if [ -d "$RECOVERY_DIR" ]; then
                [ ! -f "$KIOSK_DIR/index.html" ] && [ -f "$RECOVERY_DIR/kiosk/index.html" ] && \
                    cp -f "$RECOVERY_DIR/kiosk/index.html" "$KIOSK_DIR/index.html"
                [ ! -f "$KIOSK_DIR/serve.py" ] && [ -f "$RECOVERY_DIR/kiosk/serve.py" ] && \
                    cp -f "$RECOVERY_DIR/kiosk/serve.py" "$KIOSK_DIR/serve.py"
                [ ! -f "$HOME/alfredo-bridge.py" ] && [ -f "$RECOVERY_DIR/bridge/alfredo-bridge.py" ] && \
                    cp -f "$RECOVERY_DIR/bridge/alfredo-bridge.py" "$HOME/alfredo-bridge.py"
                FIXED[$component]="restored from recovery"
                return 0
            fi
            return 1
            ;;

        *)
            return 1
            ;;
    esac
}

# ══════════════��═══════════════════════════════════════════
#  MAIN LOGIC
# ════════════════════════════��═════════════════════════════

# Run diagnostics
diagnose

# All healthy?
if [ ${#BROKEN[@]} -eq 0 ]; then
    log "OK: all systems healthy"
    TARGETED_FIXES=0
    BROAD_RESTARTS=0
    REBOOT_COUNT=0
    LAST_GOOD=$(date +%s)
    save_state
    exit 0
fi

# Log what's broken
for comp in "${!BROKEN[@]}"; do
    log "BROKEN: $comp — ${BROKEN[$comp]%%|*}"
done

# ── LEVEL 1: Targeted fixes ─��───────────────────────────
TARGETED_FIXES=$((TARGETED_FIXES + 1))

if [ "$TARGETED_FIXES" -le "$MAX_TARGETED_FIXES" ]; then
    log "L1: targeted fix (attempt $TARGETED_FIXES/$MAX_TARGETED_FIXES)"

    FIX_COUNT=0
    FAIL_COUNT=0
    for comp in "${!BROKEN[@]}"; do
        if try_fix "$comp"; then
            log "FIXED: $comp — ${FIXED[$comp]:-unknown}"
            FIX_COUNT=$((FIX_COUNT + 1))
        else
            log "STILL BROKEN: $comp"
            FAIL_COUNT=$((FAIL_COUNT + 1))
        fi
    done

    if [ "$FAIL_COUNT" -eq 0 ]; then
        log "L1: all issues resolved"
        TARGETED_FIXES=0
        BROAD_RESTARTS=0
        REBOOT_COUNT=0
        LAST_GOOD=$(date +%s)
    fi

    save_state
    exit 0
fi

# ── LEVEL 2: Broad restart ──────────��───────────────────
BROAD_RESTARTS=$((BROAD_RESTARTS + 1))

if [ "$BROAD_RESTARTS" -le "$MAX_BROAD_RESTARTS" ]; then
    log "L2: broad service restart (attempt $BROAD_RESTARTS/$MAX_BROAD_RESTARTS)"
    TARGETED_FIXES=0

    # Kill everything and restart clean
    pkill -f "python.*serve.py" 2>/dev/null || true
    pkill -f "chromium" 2>/dev/null || true
    sleep 2

    sudo systemctl restart alfredo-kiosk-web 2>/dev/null || true
    sudo systemctl restart alfredo-bridge 2>/dev/null || true
    sudo systemctl restart alfredo-wake 2>/dev/null || true
    sleep 5

    # Relaunch chromium
    if curl -sf --max-time 5 http://localhost:8430/ >/dev/null 2>&1; then
        export WAYLAND_DISPLAY=wayland-0
        export XDG_RUNTIME_DIR=/run/user/1000
        local url="http://localhost:8430/boot-splash.html"
        curl -sf --max-time 2 "$url" >/dev/null 2>&1 || url="http://localhost:8430/"
        chromium --kiosk --ozone-platform=wayland --noerrdialogs --no-first-run \
            --disable-infobars --disable-session-crashed-bubble \
            --start-fullscreen --autoplay-policy=no-user-gesture-required \
            "$url" &>/dev/null &
    fi

    save_state
    exit 0
fi

# ── LEVEL 3: Reboot ─────────────────────────────────────
if [ "$REBOOT_COUNT" -lt "$MAX_REBOOTS" ]; then
    REBOOT_COUNT=$((REBOOT_COUNT + 1))
    TARGETED_FIXES=0
    BROAD_RESTARTS=0

    log "L3: rebooting (attempt $REBOOT_COUNT/$MAX_REBOOTS)"

    # Log unresolved issues before reboot
    for comp in "${!BROKEN[@]}"; do
        if [ -z "${FIXED[$comp]:-}" ]; then
            log_issue "$comp" "Persistent failure — survived targeted fixes and broad restarts" "${BROKEN[$comp]}"
        fi
    done

    save_state
    espeak-ng "Rebooting. Attempt $REBOOT_COUNT." 2>/dev/null || true
    sudo reboot
    exit 0
fi

# ── LEVEL 4: Full rebuild from recovery ──���──────────────
log "L4: FULL REBUILD — all other options exhausted"

# Log everything still broken
for comp in "${!BROKEN[@]}"; do
    if [ -z "${FIXED[$comp]:-}" ]; then
        log_issue "$comp" "Unfixable — triggering full rebuild" "${BROKEN[$comp]}"
    fi
done

espeak-ng "All recovery attempts failed. Initiating full system rebuild." 2>/dev/null || true

if [ ! -f "$RECOVERY_DIR/recover-local.sh" ]; then
    log "FATAL: $RECOVERY_DIR/recover-local.sh not found — cannot self-rebuild"
    log_issue "recovery-partition" "Recovery partition missing — manual intervention required" "No recover-local.sh at $RECOVERY_DIR"
    TARGETED_FIXES=0
    BROAD_RESTARTS=0
    REBOOT_COUNT=0
    save_state
    exit 1
fi

log "Running $RECOVERY_DIR/recover-local.sh"
bash "$RECOVERY_DIR/recover-local.sh" >> /var/log/alfredo-rebuild.log 2>&1
RC=$?

TARGETED_FIXES=0
BROAD_RESTARTS=0
REBOOT_COUNT=0

if [ $RC -eq 0 ]; then
    log "Rebuild complete. Rebooting."
    LAST_GOOD=$(date +%s)
    save_state
    sudo reboot
else
    log "FATAL: rebuild failed (rc=$RC). See /var/log/alfredo-rebuild.log"
    log_issue "full-rebuild" "Local rebuild script failed with rc=$RC" "$(tail -20 /var/log/alfredo-rebuild.log 2>/dev/null || echo 'no log')"
    save_state
fi
