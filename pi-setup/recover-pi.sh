#!/usr/bin/env bash
set -euo pipefail

# ═══════════════════════════════════════════════════════════════
#  ALFREDO PI RECOVERY — resilient, autonomous, retry-capable
#  Run from Mac:  cd ~/Projects/project\ alfredo && bash pi-setup/recover-pi.sh
# ═══════════════════════════════════════════════════════════════

PI="${1:-pihub.local}"
LOCAL_MODE=false
[[ "${1:-}" == "--local" ]] && LOCAL_MODE=true && PI="localhost"
PI_USER="todd"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
KIOSK_SRC="$PROJECT_DIR/pi-kiosk"
SETUP_SRC="$PROJECT_DIR/pi-setup"
LOG="/tmp/alfredo-recovery-$(date +%Y%m%d-%H%M%S).log"

# Failure tracking for retry
declare -a FAILED_STEPS=()
declare -A STEP_CMDS=()

# ── Colors ────────────────────────────────────────────────
C="\033[38;5;45m"; G="\033[38;5;40m"; Y="\033[38;5;220m"
RED="\033[38;5;196m"; D="\033[38;5;240m"; B="\033[1m"; R="\033[0m"

status_line() {
    local label="$1" state="$2" detail="${3:-}"
    local color="" icon=""
    case "$state" in
        ok)   color="$G"; icon="●" ;;
        fail) color="$RED"; icon="✗" ;;
        warn) color="$Y"; icon="◐" ;;
        retry) color="$Y"; icon="↻" ;;
        skip) color="$D"; icon="○" ;;
    esac
    if [ -n "$detail" ]; then
        printf "  ${color}${icon}${R}  %-38s ${D}%s${R}\n" "$label" "$detail"
    else
        printf "  ${color}${icon}${R}  %-38s\n" "$label"
    fi
}

pi_run() {
    if $LOCAL_MODE; then
        bash -c "$1" 2>&1
    else
        ssh -o ConnectTimeout=15 -o LogLevel=ERROR "$PI_USER@$PI" "bash -c '$1'" 2>&1
    fi
}

pi_run_script() {
    if $LOCAL_MODE; then
        bash -s 2>&1 <<< "$1"
    else
        ssh -o ConnectTimeout=15 -o LogLevel=ERROR "$PI_USER@$PI" 'bash -s' 2>&1 <<< "$1"
    fi
}

# Run a step, track failures for retry
run_step() {
    local label="$1" retry_key="$2"
    shift 2
    local cmd_desc="$*"

    printf "\r  ${Y}◑${R}  %-38s ${D}...${R}" "$label"

    local out="" rc=0
    out=$("$@" 2>&1) || rc=$?

    echo "=== $label (rc=$rc) ===" >> "$LOG"
    echo "$out" >> "$LOG"

    if [ $rc -eq 0 ]; then
        printf "\r  ${G}●${R}  %-38s\n" "$label"
        return 0
    else
        printf "\r  ${RED}✗${R}  %-38s" "$label"
        local err_line
        err_line=$(echo "$out" | grep -iE 'error|fail|denied|not found|unable|cannot' | head -1 | cut -c1-70)
        if [ -n "$err_line" ]; then
            printf " ${D}%s${R}\n" "$err_line"
        else
            printf "\n"
        fi
        # Track for retry
        if [ -n "$retry_key" ]; then
            FAILED_STEPS+=("$retry_key")
        fi
        return 1
    fi
}

# Install an apt package with fallback strategies
apt_install() {
    local label="$1" pkg="$2" alt_pkg="${3:-}"

    # Already installed?
    if pi_run "dpkg -s $pkg &>/dev/null" 2>/dev/null; then
        status_line "$label" ok "installed"
        return 0
    fi

    # Strategy 1: normal apt install
    printf "\r  ${Y}◑${R}  %-38s ${D}...${R}" "$label"
    local out="" rc=0
    out=$(pi_run "sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq $pkg" 2>&1) || rc=$?

    if [ $rc -eq 0 ]; then
        printf "\r  ${G}●${R}  %-38s\n" "$label"
        echo "=== apt: $pkg OK ===" >> "$LOG"
        return 0
    fi

    # Strategy 2: try alternate package name
    if [ -n "$alt_pkg" ]; then
        echo "=== apt: $pkg failed (rc=$rc), trying $alt_pkg ===" >> "$LOG"
        echo "$out" >> "$LOG"
        out=$(pi_run "sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq $alt_pkg" 2>&1) || rc=$?
        if [ $rc -eq 0 ]; then
            printf "\r  ${G}●${R}  %-38s ${D}(as $alt_pkg)${R}\n" "$label"
            return 0
        fi
    fi

    # Strategy 3: fix broken packages, update cache, retry
    echo "=== apt: retrying $pkg after fix ===" >> "$LOG"
    pi_run "sudo dpkg --configure -a 2>/dev/null; sudo apt-get -f install -y -qq 2>/dev/null; sudo apt-get update -qq 2>/dev/null" >> "$LOG" 2>&1 || true
    out=$(pi_run "sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq $pkg" 2>&1) || rc=$?
    if [ $rc -eq 0 ]; then
        printf "\r  ${G}●${R}  %-38s ${D}(after fix)${R}\n" "$label"
        return 0
    fi

    # Failed all strategies
    printf "\r  ${RED}✗${R}  %-38s\n" "$label"
    local err=$(echo "$out" | grep -iE 'error|unable' | head -1 | cut -c1-60)
    [ -n "$err" ] && printf "     ${RED}→ %s${R}\n" "$err"
    echo "=== apt: $pkg ALL STRATEGIES FAILED ===" >> "$LOG"
    echo "$out" >> "$LOG"
    FAILED_STEPS+=("apt:$pkg")
    return 1
}

# Install a pip package with fallback strategies
pip_install() {
    local label="$1" pkg="$2"

    # Already installed?
    local import_name="${pkg%%[*}"  # strip extras like httpx[http2] → httpx
    import_name="${import_name//-/_}"  # PyJWT → PyJWT (pip name), but import is jwt...
    # Just try the install — pip will skip if satisfied
    printf "\r  ${Y}◑${R}  %-38s ${D}...${R}" "$label"

    local out="" rc=0
    out=$(pi_run "pip3 install --break-system-packages --quiet '$pkg' 2>&1 | grep -v DEPRECATION | grep -v 'already satisfied'" 2>&1) || rc=$?

    if [ $rc -eq 0 ]; then
        printf "\r  ${G}●${R}  %-38s\n" "$label"
        echo "=== pip: $pkg OK ===" >> "$LOG"
        return 0
    fi

    # Strategy 2: install build deps and retry
    echo "=== pip: $pkg failed, retrying with build deps ===" >> "$LOG"
    echo "$out" >> "$LOG"
    pi_run "sudo apt-get install -y -qq python3-dev build-essential" >> "$LOG" 2>&1 || true
    out=$(pi_run "pip3 install --break-system-packages --quiet '$pkg' 2>&1 | grep -v DEPRECATION" 2>&1) || rc=$?
    if [ $rc -eq 0 ]; then
        printf "\r  ${G}●${R}  %-38s ${D}(with build deps)${R}\n" "$label"
        return 0
    fi

    # Strategy 3: install without binary (compile from source)
    echo "=== pip: $pkg retrying --no-binary ===" >> "$LOG"
    out=$(pi_run "pip3 install --break-system-packages --no-binary :all: '$pkg' 2>&1 | tail -3" 2>&1) || rc=$?
    if [ $rc -eq 0 ]; then
        printf "\r  ${G}●${R}  %-38s ${D}(compiled)${R}\n" "$label"
        return 0
    fi

    printf "\r  ${RED}✗${R}  %-38s\n" "$label"
    FAILED_STEPS+=("pip:$pkg")
    return 1
}

echo ""
echo -e "${C}╔══════════════════════════════════════════════════╗${R}"
echo -e "${C}║${R}  ${B}ALFREDO PI RECOVERY${R}                              ${C}║${R}"
echo -e "${C}╚══════════════════════════════════════════════════╝${R}"
echo -e "  ${D}Log: $LOG${R}"
echo ""

# ══════════════════════════════════════════════════════════
#  PHASE 1: CONNECTIVITY
# ══════════════════════════════════════════════════════════
echo -e "  ${B}CONNECTIVITY${R}"

if $LOCAL_MODE; then
    status_line "Network discovery" ok "local mode"
else
    FOUND=false
    if ping -c 1 -W 3 "$PI" &>/dev/null 2>&1; then
        FOUND=true
        status_line "Network discovery" ok "$PI"
    else
        PI_IP=$(timeout 5 dns-sd -G v4 "$PI" 2>&1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | head -1 || true)
        if [ -n "${PI_IP:-}" ]; then
            PI="$PI_IP"
            FOUND=true
            status_line "Network discovery" warn "resolved → $PI_IP"
        fi
    fi
    if ! $FOUND; then
        status_line "Network discovery" fail "Pi not found"
        exit 1
    fi

    # Clear stale host keys
    ssh-keygen -R "$PI" &>/dev/null || true
    ssh-keygen -R pihub.local &>/dev/null || true
    RESOLVED_IP=$(getent hosts "$PI" 2>/dev/null | awk '{print $1}' || true)
    [ -n "$RESOLVED_IP" ] && ssh-keygen -R "$RESOLVED_IP" &>/dev/null || true
    status_line "Host key cleanup" ok

    # SSH auth
    if ssh -o ConnectTimeout=10 -o BatchMode=yes -o StrictHostKeyChecking=accept-new "$PI_USER@$PI" 'true' &>/dev/null; then
        status_line "SSH key auth" ok
    else
        status_line "SSH key auth" warn "pushing key..."
        if ssh-copy-id -o StrictHostKeyChecking=accept-new "$PI_USER@$PI" &>"$LOG.sshcopy"; then
            status_line "SSH key install" ok
        else
            status_line "SSH key install" fail "check password"
            exit 1
        fi
    fi
fi

# ══════════════════════════════════════════════════════════
#  PHASE 2: SYSTEM PACKAGES
# ══════════════════════════════════════════════════════════
echo ""
echo -e "  ${B}SYSTEM PACKAGES${R}"

run_step "Wait for apt lock" "apt-lock" pi_run '
for i in $(seq 1 30); do
    fuser /var/lib/dpkg/lock-frontend &>/dev/null 2>&1 || exit 0
    sleep 4
done
sudo killall -9 packagekitd unattended-upgrade apt 2>/dev/null || true
sleep 2
' || true

run_step "apt update" "apt-update" pi_run 'sudo DEBIAN_FRONTEND=noninteractive apt-get update -qq' || true

apt_install "python3"           python3
apt_install "python3-pip"       python3-pip
apt_install "python3-venv"      python3-venv
apt_install "curl"              curl
apt_install "jq"                jq
apt_install "fail2ban"          fail2ban
apt_install "ufw"               ufw
apt_install "network-manager"   network-manager
apt_install "chromium"          chromium chromium-browser
apt_install "portaudio19-dev"   portaudio19-dev
apt_install "python3-pyaudio"   python3-pyaudio
apt_install "libopus0"          libopus0
apt_install "ffmpeg"            ffmpeg
apt_install "wlr-randr"        wlr-randr
apt_install "espeak-ng"        espeak-ng
apt_install "git"              git

# ══════════════════════════════════════════════════════════
#  PHASE 3: FILES
# ══════════════════════════════════════════════════════════
echo ""
echo -e "  ${B}DEPLOY FILES${R}"

run_step "Create directories" "" pi_run 'mkdir -p ~/alfredo-kiosk ~/alfredo-kiosk/issues ~/alfredo-bridge ~/.config/labwc ~/piper-voices' || true

# Init git in kiosk dir for issue tracking
run_step "Init git (issue tracking)" "" pi_run '
if [ ! -d ~/alfredo-kiosk/.git ]; then
    cd ~/alfredo-kiosk && git init -q && git add -A && git commit -q -m "initial kiosk state" 2>/dev/null || true
fi
' || true

KIOSK_FILES=(index.html serve.py calendar-feeds.json settings.html editor.html setup-voice.sh)
for f in "${KIOSK_FILES[@]}"; do
    if [ -f "$KIOSK_SRC/$f" ]; then
        run_step "kiosk/$f" "file:kiosk/$f" scp -q "$KIOSK_SRC/$f" "$PI_USER@$PI:~/alfredo-kiosk/$f" || true
    else
        status_line "kiosk/$f" skip "not found locally"
    fi
done

if [ -f "$SETUP_SRC/boot-splash.html" ]; then
    run_step "boot-splash.html" "file:boot-splash" scp -q "$SETUP_SRC/boot-splash.html" "$PI_USER@$PI:~/alfredo-kiosk/boot-splash.html" || true
fi

SETUP_FILES=(
    "alfredo-bridge.py:~/alfredo-bridge.py"
    "alfredo-wake.py:~/alfredo-kiosk/alfredo-wake.py"
    "apns-send.py:~/alfredo-kiosk/apns-send.py"
    "alfredo-watchdog.sh:~/alfredo-bridge/alfredo-watchdog.sh"
    "alfredo-self-heal.sh:~/alfredo-bridge/alfredo-self-heal.sh"
    "persona.md:~/alfredo-kiosk/persona.md"
    "labwc-autostart:~/.config/labwc/autostart"
)
for entry in "${SETUP_FILES[@]}"; do
    src="${entry%%:*}"; dst="${entry##*:}"
    run_step "$src" "file:$src" scp -q "$SETUP_SRC/$src" "$PI_USER@$PI:$dst" || true
done

# ══════════════════════════════════════════════════════════
#  PHASE 4: PYTHON
# ══════════════════════════════════════════════════════════
echo ""
echo -e "  ${B}PYTHON PACKAGES${R}"

run_step "Bridge venv + websockets" "pip:websockets" pi_run '
[ ! -d ~/alfredo-venv ] && python3 -m venv ~/alfredo-venv
~/alfredo-venv/bin/pip install --quiet websockets 2>&1 | grep -v DEPRECATION || true
' || true

pip_install "pyaudio"          pyaudio
pip_install "webrtcvad"        webrtcvad
pip_install "openai-whisper"   openai-whisper
pip_install "httpx"            "httpx[http2]"
pip_install "PyJWT"            PyJWT
pip_install "cryptography"     cryptography

run_step "Whisper model (tiny.en)" "" pi_run 'python3 -c "import whisper; whisper.load_model(\"tiny.en\")" 2>/dev/null' || true

# ══════════════════════════════════════════════════════════
#  PHASE 5: SERVICES & SECURITY
# ══════════════════════════════════════════════════════════
echo ""
echo -e "  ${B}SERVICES & SECURITY${R}"

for svc in alfredo-bridge.service alfredo-kiosk-web.service alfredo-watchdog.service alfredo-watchdog.timer alfredo-wake.service alfredo-self-heal.service alfredo-self-heal.timer; do
    if [ -f "$SETUP_SRC/$svc" ]; then
        run_step "$svc" "svc:$svc" bash -c "scp -q '$SETUP_SRC/$svc' '$PI_USER@$PI:/tmp/$svc' && ssh -o LogLevel=ERROR '$PI_USER@$PI' 'sudo mv /tmp/$svc /etc/systemd/system/$svc'" || true
    fi
done

run_step "systemctl daemon-reload" "" pi_run 'sudo systemctl daemon-reload' || true
run_step "Enable services" "" pi_run 'sudo systemctl enable alfredo-bridge alfredo-kiosk-web alfredo-watchdog.timer alfredo-wake alfredo-self-heal.timer 2>&1' || true
run_step "File permissions" "" pi_run 'chmod +x ~/alfredo-bridge.py ~/alfredo-bridge/alfredo-watchdog.sh ~/alfredo-bridge/alfredo-self-heal.sh ~/.config/labwc/autostart 2>/dev/null' || true

run_step "Firewall (ufw)" "" pi_run '
sudo ufw default deny incoming &>/dev/null
sudo ufw default allow outgoing &>/dev/null
sudo ufw allow ssh &>/dev/null
sudo ufw allow 8420/tcp &>/dev/null
sudo ufw allow 8421/tcp &>/dev/null
sudo ufw allow 8430/tcp &>/dev/null
echo "y" | sudo ufw enable &>/dev/null
' || true

run_step "SSH hardening" "" pi_run_script '
sudo cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak 2>/dev/null || true
for pair in "PasswordAuthentication no" "PermitRootLogin no" "MaxAuthTries 3" "ClientAliveInterval 60" "ClientAliveCountMax 3" "TCPKeepAlive yes"; do
    key="${pair%% *}"; val="${pair#* }"
    if grep -q "^${key}" /etc/ssh/sshd_config; then
        sudo sed -i "s/^${key}.*/${key} ${val}/" /etc/ssh/sshd_config
    else
        echo "${key} ${val}" | sudo tee -a /etc/ssh/sshd_config >/dev/null
    fi
done
sudo systemctl restart ssh
' || true

run_step "Fail2ban" "" pi_run_script '
sudo mkdir -p /etc/fail2ban/jail.d
sudo tee /etc/fail2ban/jail.d/alfredo.conf > /dev/null <<INNER
[sshd]
enabled = true
port = ssh
maxretry = 5
bantime = 3600
findtime = 600
INNER
sudo systemctl enable --now fail2ban &>/dev/null
sudo systemctl restart fail2ban
' || true

run_step "WiFi keepalive" "" pi_run_script '
sudo mkdir -p /etc/NetworkManager/conf.d
sudo tee /etc/NetworkManager/conf.d/alfredo-keepalive.conf > /dev/null <<INNER
[connection]
wifi.powersave = 2
[connectivity]
interval = 60
uri = http://nmcheck.gnome.org/check_network_status.txt
INNER
sudo systemctl restart NetworkManager 2>/dev/null || true
' || true

run_step "Sudoers (watchdog)" "" pi_run_script '
sudo tee /etc/sudoers.d/alfredo-watchdog > /dev/null <<INNER
todd ALL=(ALL) NOPASSWD: /usr/bin/systemctl restart alfredo-bridge
todd ALL=(ALL) NOPASSWD: /usr/bin/systemctl restart alfredo-kiosk-web
todd ALL=(ALL) NOPASSWD: /usr/bin/systemctl restart alfredo-wake
todd ALL=(ALL) NOPASSWD: /usr/bin/systemctl restart NetworkManager
todd ALL=(ALL) NOPASSWD: /usr/bin/systemctl restart dhcpcd
todd ALL=(ALL) NOPASSWD: /sbin/reboot
INNER
sudo chmod 440 /etc/sudoers.d/alfredo-watchdog
' || true

run_step "Presence config" "" pi_run '
[ ! -f ~/alfredo-kiosk/presence.json ] && echo "{\"hosts\":[\"todds-MacBook-Pro.local\"],\"interval\":15}" > ~/alfredo-kiosk/presence.json || true
' || true

# ══════════════════════════════════════════════════════════
#  PHASE 6: RETRY FAILURES
# ══════════════════════════════════════════════════════════
if [ ${#FAILED_STEPS[@]} -gt 0 ]; then
    echo ""
    echo -e "  ${B}RETRY FAILURES${R} ${D}(${#FAILED_STEPS[@]} items)${R}"

    # Refresh apt cache before retrying
    pi_run 'sudo dpkg --configure -a 2>/dev/null; sudo apt-get -f install -y -qq 2>/dev/null; sudo apt-get update -qq 2>/dev/null' >> "$LOG" 2>&1 || true

    STILL_FAILED=()
    for item in "${FAILED_STEPS[@]}"; do
        case "$item" in
            apt:*)
                pkg="${item#apt:}"
                printf "\r  ${Y}↻${R}  %-38s ${D}retry...${R}" "apt: $pkg"
                if pi_run "sudo DEBIAN_FRONTEND=noninteractive apt-get install -y $pkg" >> "$LOG" 2>&1; then
                    printf "\r  ${G}●${R}  %-38s ${D}(retry OK)${R}\n" "apt: $pkg"
                else
                    printf "\r  ${RED}✗${R}  %-38s ${D}(retry failed)${R}\n" "apt: $pkg"
                    STILL_FAILED+=("$item")
                fi
                ;;
            pip:*)
                pkg="${item#pip:}"
                printf "\r  ${Y}↻${R}  %-38s ${D}retry...${R}" "pip: $pkg"
                if pi_run "pip3 install --break-system-packages '$pkg'" >> "$LOG" 2>&1; then
                    printf "\r  ${G}●${R}  %-38s ${D}(retry OK)${R}\n" "pip: $pkg"
                else
                    printf "\r  ${RED}✗${R}  %-38s ${D}(retry failed)${R}\n" "pip: $pkg"
                    STILL_FAILED+=("$item")
                fi
                ;;
            file:*)
                fname="${item#file:}"
                printf "\r  ${Y}↻${R}  %-38s ${D}retry...${R}" "$fname"
                # Try rsync as fallback to scp
                if scp -q "$SETUP_SRC/$fname" "$PI_USER@$PI:~/alfredo-kiosk/" 2>/dev/null || \
                   scp -q "$KIOSK_SRC/$fname" "$PI_USER@$PI:~/alfredo-kiosk/" 2>/dev/null; then
                    printf "\r  ${G}●${R}  %-38s ${D}(retry OK)${R}\n" "$fname"
                else
                    printf "\r  ${RED}✗${R}  %-38s ${D}(retry failed)${R}\n" "$fname"
                    STILL_FAILED+=("$item")
                fi
                ;;
            *)
                STILL_FAILED+=("$item")
                ;;
        esac
    done
    FAILED_STEPS=("${STILL_FAILED[@]}")
fi

# ══════════════════════════════════════════════════════════
#  PHASE 7: START & VERIFY
# ══════════════════════════════════════════════════════════
echo ""
echo -e "  ${B}START & VERIFY${R}"

run_step "Start kiosk web" "" pi_run 'sudo systemctl start alfredo-kiosk-web' || true
sleep 2
run_step "Start bridge" "" pi_run 'sudo systemctl start alfredo-bridge' || true
run_step "Start watchdog" "" pi_run 'sudo systemctl start alfredo-watchdog.timer' || true
run_step "Start wake listener" "" pi_run 'sudo systemctl start alfredo-wake 2>&1' || true
run_step "Start self-heal" "" pi_run 'sudo systemctl start alfredo-self-heal.timer' || true
sleep 3

echo ""
echo -e "  ${B}HEALTH CHECK${R}"

for svc in alfredo-kiosk-web alfredo-bridge alfredo-watchdog.timer alfredo-wake alfredo-self-heal.timer; do
    STATUS=$(pi_run "systemctl is-active $svc 2>/dev/null" || echo "inactive")
    case "$STATUS" in
        active)   status_line "$svc" ok "running" ;;
        inactive) status_line "$svc" warn "inactive" ;;
        failed)
            REASON=$(pi_run "journalctl -u $svc --no-pager -n 1 2>/dev/null | tail -1" || echo "")
            status_line "$svc" fail "${REASON:0:60}"
            ;;
        *)        status_line "$svc" warn "$STATUS" ;;
    esac
done

KIOSK_OK=$(pi_run 'curl -sf --max-time 5 http://localhost:8430/ >/dev/null && echo yes || echo no')
[[ "$KIOSK_OK" == *"yes"* ]] && status_line "Kiosk HTTP :8430" ok "responding" || status_line "Kiosk HTTP :8430" warn "not yet"

BRIDGE_OK=$(pi_run 'curl -sf --max-time 5 http://localhost:8420/health 2>/dev/null && echo yes || echo no')
[[ "$BRIDGE_OK" == *"yes"* ]] && status_line "Bridge HTTP :8420" ok "healthy" || status_line "Bridge HTTP :8420" warn "needs Claude CLI"

# ══════════════════════════════════════════════════════════
#  SUMMARY
# ══════════════════════════════════════════════════════════
echo ""
NERR=${#FAILED_STEPS[@]}
if [ "$NERR" -eq 0 ]; then
    echo -e "${C}╔══════════════════════════════════════════════════╗${R}"
    echo -e "${C}║${R}  ${G}● ALL SYSTEMS GREEN${R}                              ${C}║${R}"
    echo -e "${C}╚══════════════════════════════════════════════════╝${R}"
else
    echo -e "${C}╔══════════════════════════════════════════════════╗${R}"
    echo -e "${C}║${R}  ${Y}◐ COMPLETE — $NERR item(s) failed after retry${R}       ${C}║${R}"
    echo -e "${C}╚══════════════════════════════════════════════════╝${R}"
    echo ""
    echo -e "  ${RED}Failed:${R}"
    for item in "${FAILED_STEPS[@]}"; do
        echo "    - $item"
    done
fi
echo ""
echo -e "  ${D}Full log: $LOG${R}"
echo ""
echo -e "  ${B}Next steps:${R}"
echo "    1. ssh $PI 'curl -fsSL https://claude.ai/install.sh | sh'"
echo "    2. ssh $PI 'echo ANTHROPIC_API_KEY=sk-... >> ~/.bashrc'"
echo "    3. Piper voice model:"
echo "       ssh $PI 'wget -qO ~/piper-voices/en_US-lessac-medium.onnx \\
         https://huggingface.co/rhasspy/piper-voices/resolve/main/en/en_US/lessac/medium/en_US-lessac-medium.onnx'"
echo "    4. Recovery partition (self-healing):"
echo "       bash pi-setup/setup-recovery-partition.sh"
echo "    5. Reboot: ssh $PI 'sudo reboot'"
echo ""
