#!/usr/bin/env bash
set -euo pipefail

# ═══════════════════════════════════════════════════════════════
#  SETUP RECOVERY PARTITION — populate /boot/alfredo-recovery/
#  Run from Mac after initial recovery is complete:
#    bash pi-setup/setup-recovery-partition.sh
#
#  This copies all alfredo files to the Pi's boot partition so
#  the self-heal system can rebuild without network access.
#  Also installs the self-heal timer.
# ═══════════════════════════════════════════════════════════════

PI="${1:-pihub.local}"
PI_USER="todd"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
KIOSK_SRC="$PROJECT_DIR/pi-kiosk"
SETUP_SRC="$PROJECT_DIR/pi-setup"

C="\033[38;5;45m"; G="\033[38;5;40m"; Y="\033[38;5;220m"
D="\033[38;5;240m"; B="\033[1m"; R="\033[0m"; RED="\033[38;5;196m"

ok()   { printf "  ${G}●${R}  %-40s\n" "$1"; }
fail() { printf "  ${RED}✗${R}  %-40s\n" "$1"; }

pi_ssh() { ssh -o ConnectTimeout=10 -o LogLevel=ERROR "$PI_USER@$PI" "$@"; }

echo ""
echo -e "${C}╔══════════════════════════════════════════════════╗${R}"
echo -e "${C}║${R}  ${B}SETUP RECOVERY PARTITION${R}                         ${C}║${R}"
echo -e "${C}╚══════════════════════════════════════════════════╝${R}"
echo ""

# Create directory structure on Pi
pi_ssh 'sudo mkdir -p /boot/alfredo-recovery/{kiosk,bridge,services,config}'
pi_ssh 'sudo chown -R todd:todd /boot/alfredo-recovery'
ok "Created /boot/alfredo-recovery/"

# Kiosk files
echo -e "  ${B}Kiosk files:${R}"
for f in index.html serve.py settings.html editor.html setup-voice.sh; do
    if [ -f "$KIOSK_SRC/$f" ]; then
        scp -q "$KIOSK_SRC/$f" "$PI_USER@$PI:/boot/alfredo-recovery/kiosk/$f" && ok "  kiosk/$f" || fail "  kiosk/$f"
    fi
done

# Boot splash
scp -q "$SETUP_SRC/boot-splash.html" "$PI_USER@$PI:/boot/alfredo-recovery/boot-splash.html" && ok "  boot-splash.html" || fail "  boot-splash.html"
scp -q "$SETUP_SRC/boot-splash.html" "$PI_USER@$PI:/boot/alfredo-recovery/kiosk/boot-splash.html" && ok "  kiosk/boot-splash.html" || fail "  kiosk/boot-splash.html"

# Labwc autostart
scp -q "$SETUP_SRC/labwc-autostart" "$PI_USER@$PI:/boot/alfredo-recovery/labwc-autostart" && ok "  labwc-autostart" || fail "  labwc-autostart"

# Bridge files
echo -e "  ${B}Bridge files:${R}"
scp -q "$SETUP_SRC/alfredo-bridge.py" "$PI_USER@$PI:/boot/alfredo-recovery/bridge/alfredo-bridge.py" && ok "  bridge/alfredo-bridge.py" || fail "  bridge/alfredo-bridge.py"
scp -q "$SETUP_SRC/alfredo-watchdog.sh" "$PI_USER@$PI:/boot/alfredo-recovery/bridge/alfredo-watchdog.sh" && ok "  bridge/alfredo-watchdog.sh" || fail "  bridge/alfredo-watchdog.sh"
scp -q "$SETUP_SRC/alfredo-self-heal.sh" "$PI_USER@$PI:/boot/alfredo-recovery/bridge/alfredo-self-heal.sh" && ok "  bridge/alfredo-self-heal.sh" || fail "  bridge/alfredo-self-heal.sh"

# Config files
echo -e "  ${B}Config files:${R}"
scp -q "$SETUP_SRC/persona.md" "$PI_USER@$PI:/boot/alfredo-recovery/config/persona.md" && ok "  config/persona.md" || fail "  config/persona.md"
scp -q "$KIOSK_SRC/calendar-feeds.json" "$PI_USER@$PI:/boot/alfredo-recovery/config/calendar-feeds.json" && ok "  config/calendar-feeds.json" || fail "  config/calendar-feeds.json"
pi_ssh 'echo "{\"hosts\":[\"todds-MacBook-Pro.local\"],\"interval\":15}" > /boot/alfredo-recovery/config/presence.json'
ok "  config/presence.json"

# Recovery script
scp -q "$SETUP_SRC/recover-local.sh" "$PI_USER@$PI:/boot/alfredo-recovery/recover-local.sh" && ok "  recover-local.sh" || fail "  recover-local.sh"

# Systemd services
echo -e "  ${B}Service files:${R}"
for svc in alfredo-bridge.service alfredo-kiosk-web.service alfredo-watchdog.service alfredo-watchdog.timer alfredo-wake.service alfredo-self-heal.service alfredo-self-heal.timer; do
    if [ -f "$SETUP_SRC/$svc" ]; then
        scp -q "$SETUP_SRC/$svc" "$PI_USER@$PI:/boot/alfredo-recovery/services/$svc" && ok "  services/$svc" || fail "  services/$svc"
    fi
done

# Set permissions
pi_ssh 'chmod +x /boot/alfredo-recovery/recover-local.sh /boot/alfredo-recovery/bridge/*.sh 2>/dev/null'

# Install self-heal timer + service
echo ""
echo -e "  ${B}Install self-heal:${R}"
scp -q "$SETUP_SRC/alfredo-self-heal.sh" "$PI_USER@$PI:~/alfredo-bridge/alfredo-self-heal.sh"
pi_ssh 'chmod +x ~/alfredo-bridge/alfredo-self-heal.sh'
scp -q "$SETUP_SRC/alfredo-self-heal.service" "$PI_USER@$PI:/tmp/alfredo-self-heal.service"
scp -q "$SETUP_SRC/alfredo-self-heal.timer" "$PI_USER@$PI:/tmp/alfredo-self-heal.timer"
pi_ssh 'sudo mv /tmp/alfredo-self-heal.service /tmp/alfredo-self-heal.timer /etc/systemd/system/'
pi_ssh 'sudo systemctl daemon-reload && sudo systemctl enable --now alfredo-self-heal.timer'
ok "Self-heal timer active (every 5 min)"

# Verify
echo ""
RECOVERY_SIZE=$(pi_ssh 'du -sh /boot/alfredo-recovery 2>/dev/null | cut -f1')
ok "Recovery partition: $RECOVERY_SIZE"

BOOT_FREE=$(pi_ssh 'df -h /boot | tail -1 | awk "{print \$4}"')
ok "Boot partition free: $BOOT_FREE"

echo ""
echo -e "${C}╔══════════════════════════════════════════════════╗${R}"
echo -e "${C}║${R}  ${G}● RECOVERY PARTITION READY${R}                       ${C}║${R}"
echo -e "${C}╚══════════════════════════════════════════════════╝${R}"
echo ""
echo -e "  ${B}Self-healing escalation:${R}"
echo "    1. Every 5 min: health check"
echo "    2. 3 failures:  restart services"
echo "    3. Still broken: reboot (up to 2x)"
echo "    4. Still broken: full rebuild from /boot/alfredo-recovery/"
echo ""
echo -e "  ${B}Update recovery files:${R}"
echo "    Re-run this script anytime to push latest code."
echo ""
