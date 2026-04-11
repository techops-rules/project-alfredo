#!/usr/bin/env bash
# Alfredo Watchdog — keeps the bridge and network alive
# Runs every 2 minutes via systemd timer

set -euo pipefail

LOG_TAG="alfredo-watchdog"
BRIDGE_PORT=8420
GATEWAY=$(ip route | awk '/default/ {print $3}' | head -1)

log() { logger -t "$LOG_TAG" "$*"; }

# 1. Check network connectivity
if ! ping -c 1 -W 3 "$GATEWAY" &>/dev/null; then
    log "WARN: gateway unreachable, restarting networking"
    sudo systemctl restart NetworkManager 2>/dev/null || sudo systemctl restart dhcpcd 2>/dev/null || true
    sleep 5
fi

# 2. Check bridge is responding
if ! curl -sf --max-time 5 "http://localhost:${BRIDGE_PORT}/health" &>/dev/null; then
    log "WARN: bridge not responding, restarting"
    sudo systemctl restart alfredo-bridge
fi

# 3. Check Chromium kiosk is running
if ! pgrep -f "chromium.*kiosk" &>/dev/null; then
    # Only relaunch if kiosk web server is up (avoid launching into error page)
    if curl -sf --max-time 3 http://localhost:8430/ &>/dev/null; then
        log "WARN: kiosk not running, relaunching Chromium"
        export WAYLAND_DISPLAY=wayland-0
        export XDG_RUNTIME_DIR=/run/user/1000
        chromium --kiosk --ozone-platform=wayland --noerrdialogs --no-first-run \
            --disable-infobars --disable-session-crashed-bubble \
            --start-fullscreen http://localhost:8430/ &>/dev/null &
    else
        log "WARN: kiosk not running but web server also down, skipping relaunch"
    fi
fi

log "OK: watchdog check passed"
