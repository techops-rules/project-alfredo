#!/usr/bin/env bash
set -euo pipefail

# Alfredo Pi Setup
# Run on the Pi as todd: bash ~/alfredo-bridge/setup-pi.sh
# Installs: bridge service, watchdog, SSH hardening, keepalive

BRIDGE_DIR="$HOME/alfredo-bridge"
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

step() { echo -e "\n${GREEN}==> $1${NC}"; }
warn() { echo -e "${YELLOW}    $1${NC}"; }

# ── 1. System updates ────────────────────────────────────
step "Updating system packages"
sudo apt-get update -qq
sudo apt-get upgrade -y -qq

# ── 2. Install dependencies ──────────────────────────────
step "Installing dependencies"
sudo apt-get install -y -qq \
    python3 curl jq fail2ban ufw \
    network-manager

# ── 3. Install Claude Code CLI (if missing) ──────────────
step "Checking for Claude Code CLI"
if command -v claude &>/dev/null; then
    echo "  claude cli found: $(which claude)"
else
    warn "Claude Code CLI not found."
    warn "Install it manually: npm install -g @anthropic-ai/claude-code"
    warn "Or see: https://docs.anthropic.com/claude-code"
    echo ""
    read -p "  Press Enter after installing claude, or Ctrl+C to abort..."
    if ! command -v claude &>/dev/null; then
        echo "  ERROR: claude still not found. Aborting."
        exit 1
    fi
fi

# ── 4. Deploy bridge files ───────────────────────────────
step "Deploying bridge files"
chmod +x "$BRIDGE_DIR/alfredo-bridge.py"
chmod +x "$BRIDGE_DIR/alfredo-watchdog.sh"

# ── 5. Install systemd services ──────────────────────────
step "Installing systemd services"

sudo cp "$BRIDGE_DIR/alfredo-bridge.service" /etc/systemd/system/
sudo cp "$BRIDGE_DIR/alfredo-kiosk-web.service" /etc/systemd/system/
sudo cp "$BRIDGE_DIR/alfredo-watchdog.service" /etc/systemd/system/
sudo cp "$BRIDGE_DIR/alfredo-watchdog.timer" /etc/systemd/system/

sudo systemctl daemon-reload
sudo systemctl enable --now alfredo-bridge
sudo systemctl enable --now alfredo-kiosk-web
sudo systemctl enable --now alfredo-watchdog.timer

# ── 6. Firewall ──────────────────────────────────────────
step "Configuring firewall (UFW)"
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow ssh
sudo ufw allow 8420/tcp comment "Alfredo Bridge"
echo "y" | sudo ufw enable || true
sudo ufw status

# ── 7. SSH hardening ─────────────────────────────────────
step "Hardening SSH"

# Backup original config
sudo cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak.$(date +%s) 2>/dev/null || true

# Apply hardening (only if not already set)
SSHD_CONF="/etc/ssh/sshd_config"
apply_ssh() {
    local key="$1" val="$2"
    if grep -q "^${key}" "$SSHD_CONF"; then
        sudo sed -i "s/^${key}.*/${key} ${val}/" "$SSHD_CONF"
    else
        echo "${key} ${val}" | sudo tee -a "$SSHD_CONF" >/dev/null
    fi
}

apply_ssh "PasswordAuthentication" "no"
apply_ssh "PermitRootLogin" "no"
apply_ssh "MaxAuthTries" "3"
apply_ssh "ClientAliveInterval" "60"
apply_ssh "ClientAliveCountMax" "3"
apply_ssh "TCPKeepAlive" "yes"

sudo systemctl restart ssh

# ── 8. Fail2ban for SSH ──────────────────────────────────
step "Configuring fail2ban"
sudo tee /etc/fail2ban/jail.d/alfredo.conf > /dev/null <<'EOF'
[sshd]
enabled = true
port = ssh
maxretry = 5
bantime = 3600
findtime = 600
EOF
sudo systemctl enable --now fail2ban
sudo systemctl restart fail2ban

# ── 9. Network keepalive (WiFi reconnect) ────────────────
step "Setting up WiFi keepalive"
sudo tee /etc/NetworkManager/conf.d/alfredo-keepalive.conf > /dev/null <<'EOF'
[connection]
wifi.powersave = 2

[connectivity]
interval = 60
uri = http://nmcheck.gnome.org/check_network_status.txt
EOF
sudo systemctl restart NetworkManager 2>/dev/null || true

# Allow watchdog to restart services without password
step "Configuring sudoers for watchdog"
sudo tee /etc/sudoers.d/alfredo-watchdog > /dev/null <<'EOF'
todd ALL=(ALL) NOPASSWD: /usr/bin/systemctl restart alfredo-bridge
todd ALL=(ALL) NOPASSWD: /usr/bin/systemctl restart NetworkManager
todd ALL=(ALL) NOPASSWD: /usr/bin/systemctl restart dhcpcd
todd ALL=(ALL) NOPASSWD: /sbin/reboot
EOF
sudo chmod 440 /etc/sudoers.d/alfredo-watchdog

# ── 10. Kiosk autostart (labwc) ──────────────────────────
step "Installing kiosk autostart"
mkdir -p "$HOME/.config/labwc"
cp "$BRIDGE_DIR/labwc-autostart" "$HOME/.config/labwc/autostart"
chmod +x "$HOME/.config/labwc/autostart"
cp "$BRIDGE_DIR/labwc-environment" "$HOME/.config/labwc/environment"

# ── 11. Verify ───────────────────────────────────────────
step "Verifying setup"
sleep 2

echo ""
echo "  Bridge service:"
systemctl is-active alfredo-bridge && echo "    RUNNING" || echo "    NOT RUNNING"

echo "  Watchdog timer:"
systemctl is-active alfredo-watchdog.timer && echo "    RUNNING" || echo "    NOT RUNNING"

echo "  Health check:"
if curl -sf --max-time 5 http://localhost:8420/health; then
    echo ""
    echo "    HEALTHY"
else
    echo "    NOT RESPONDING (bridge may still be starting)"
fi

echo ""
echo -e "${GREEN}==> Setup complete!${NC}"
echo "  Bridge: http://pihub.local:8420"
echo "  Logs:   journalctl -u alfredo-bridge -f"
echo "  Status: systemctl status alfredo-bridge"
