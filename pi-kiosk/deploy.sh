#!/bin/bash
# alfredo kiosk deploy — verbose terminal output
set -e

PI="pihub.local"
KIOSK_DIR="~/alfredo-kiosk"
LOCAL_DIR="$(cd "$(dirname "$0")" && pwd)"
VERSION=$(grep -o 'v0\.[0-9]*\.[0-9]*' "$LOCAL_DIR/index.html" | head -1)

C="\033[38;5;45m"   # cyan
G="\033[38;5;40m"   # green
Y="\033[38;5;220m"  # yellow
D="\033[38;5;240m"  # dim
R="\033[0m"          # reset
B="\033[1m"          # bold

echo ""
echo -e "${C}╔══════════════════════════════════════════╗${R}"
echo -e "${C}║${R}  ${B}ALFREDO KIOSK DEPLOY${R}  ${D}${VERSION}${R}"
echo -e "${C}╚══════════════════════════════════════════╝${R}"
echo ""

# --- Files to sync ---
FILES=(index.html serve.py calendar-feeds.json settings.html)
CHANGED=()

echo -e "${D}[$(date +%H:%M:%S)]${R} ${Y}DIFF${R}  checking local vs remote..."
for f in "${FILES[@]}"; do
    if [ ! -f "$LOCAL_DIR/$f" ]; then
        continue
    fi
    # Compare with remote
    LOCAL_HASH=$(md5 -q "$LOCAL_DIR/$f" 2>/dev/null || md5sum "$LOCAL_DIR/$f" | cut -d' ' -f1)
    REMOTE_HASH=$(ssh "$PI" "md5sum $KIOSK_DIR/$f 2>/dev/null | cut -d' ' -f1" 2>/dev/null || echo "missing")
    if [ "$LOCAL_HASH" != "$REMOTE_HASH" ]; then
        CHANGED+=("$f")
        SIZE=$(wc -c < "$LOCAL_DIR/$f" | tr -d ' ')
        echo -e "${D}[$(date +%H:%M:%S)]${R} ${Y}CHANGED${R}  $f  ${D}(${SIZE}b)${R}"
    else
        echo -e "${D}[$(date +%H:%M:%S)]${R} ${D}OK${R}      $f  ${D}(unchanged)${R}"
    fi
done
echo ""

if [ ${#CHANGED[@]} -eq 0 ]; then
    echo -e "${D}[$(date +%H:%M:%S)]${R} ${G}DONE${R}  nothing to deploy"
    echo ""
    exit 0
fi

# --- Deploy changed files ---
echo -e "${D}[$(date +%H:%M:%S)]${R} ${C}SYNC${R}  deploying ${#CHANGED[@]} file(s) to ${PI}..."
for f in "${CHANGED[@]}"; do
    scp -q "$LOCAL_DIR/$f" "${PI}:${KIOSK_DIR}/$f"
    echo -e "${D}[$(date +%H:%M:%S)]${R} ${G}SENT${R}  $f → ${PI}:${KIOSK_DIR}/"
done
echo ""

# --- Check if serve.py changed → restart it ---
RESTART_SERVE=false
for f in "${CHANGED[@]}"; do
    if [ "$f" = "serve.py" ] || [ "$f" = "calendar-feeds.json" ]; then
        RESTART_SERVE=true
    fi
done

if $RESTART_SERVE; then
    echo -e "${D}[$(date +%H:%M:%S)]${R} ${Y}RESTART${R}  serve.py (config changed)..."
    ssh "$PI" "pkill -f 'python.*serve.py' 2>/dev/null; sleep 1; cd $KIOSK_DIR && nohup python3 serve.py > /tmp/serve.log 2>&1 &"
    sleep 2
    HEALTH=$(ssh "$PI" "curl -s http://localhost:8430/proxy/health 2>/dev/null" || echo '{"status":"offline"}')
    echo -e "${D}[$(date +%H:%M:%S)]${R} ${G}HEALTH${R}  bridge: $HEALTH"
fi

# --- Reload kiosk browser ---
echo -e "${D}[$(date +%H:%M:%S)]${R} ${C}RELOAD${R}  kiosk browser → ${VERSION}..."
ssh "$PI" "WAYLAND_DISPLAY=wayland-0 XDG_RUNTIME_DIR=/run/user/1000 chromium --ozone-platform=wayland 'http://localhost:8430/?v=${VERSION}' 2>/dev/null &"
echo -e "${D}[$(date +%H:%M:%S)]${R} ${G}LOADED${R}  chromium refreshed"
echo ""

# --- Verify ---
echo -e "${D}[$(date +%H:%M:%S)]${R} ${C}VERIFY${R}  running checks..."
CAL=$(ssh "$PI" "curl -s http://localhost:8430/proxy/calendar 2>/dev/null | python3 -c 'import json,sys;d=json.load(sys.stdin);print(len(d.get(\"events\",[])),\"events\",\"src:\"+d.get(\"source\",\"?\"),\"ical_age:\"+str(d.get(\"ical_fetch_age\",\"?\"))+\"s\")' 2>/dev/null" || echo "unavailable")
echo -e "${D}[$(date +%H:%M:%S)]${R} ${G}CAL${R}    $CAL"

PRESENCE=$(ssh "$PI" "curl -s http://localhost:8430/proxy/presence 2>/dev/null | python3 -c 'import json,sys;d=json.load(sys.stdin);print(\"present\" if d.get(\"present\") else \"away \"+str(d.get(\"absent_mins\",\"?\"))+\"m\")' 2>/dev/null" || echo "unavailable")
echo -e "${D}[$(date +%H:%M:%S)]${R} ${G}NEARBY${R} $PRESENCE"

SERVE_PID=$(ssh "$PI" "pgrep -f 'python.*serve.py' 2>/dev/null" || echo "not running")
echo -e "${D}[$(date +%H:%M:%S)]${R} ${G}SERVE${R}  pid: $SERVE_PID"

echo ""
echo -e "${C}╔══════════════════════════════════════════╗${R}"
echo -e "${C}║${R}  ${G}✓ DEPLOY COMPLETE${R}  ${B}${VERSION}${R}  ${D}$(date +%H:%M:%S)${R}"
echo -e "${C}╚══════════════════════════════════════════╝${R}"
echo ""
