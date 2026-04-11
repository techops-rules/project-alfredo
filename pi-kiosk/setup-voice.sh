#!/usr/bin/env bash
# setup-voice.sh — Install voice/wake word dependencies on the Pi
# Run: ssh pihub.local 'bash ~/alfredo-kiosk/setup-voice.sh'

set -euo pipefail

echo "=== Alfredo Voice Setup ==="

# System deps
echo "[1/4] Installing system packages..."
sudo apt-get update -qq
sudo apt-get install -y -qq \
    portaudio19-dev \
    python3-pyaudio \
    libopus0 \
    ffmpeg

# Python deps
echo "[2/4] Installing Python packages..."
pip3 install --break-system-packages \
    pyaudio \
    webrtcvad \
    openai-whisper \
    httpx[http2] \
    PyJWT \
    cryptography

# Download whisper tiny.en model (fastest, English-only, ~75MB)
echo "[3/4] Pre-downloading Whisper tiny.en model..."
python3 -c "import whisper; whisper.load_model('tiny.en')"

# Create config template if not exists
echo "[4/4] Creating config templates..."
if [ ! -f ~/alfredo-kiosk/apns-config.json ]; then
    cat > ~/alfredo-kiosk/apns-config.json << 'APNS_EOF'
{
    "key_path": "/home/pi/alfredo-kiosk/AuthKey_XXXXXXXXXX.p8",
    "key_id": "XXXXXXXXXX",
    "team_id": "XXXXXXXXXX",
    "bundle_id": "com.todd.alfredo",
    "sandbox": true
}
APNS_EOF
    echo "  Created apns-config.json template (edit with your Apple key info)"
fi

echo ""
echo "=== Voice setup complete ==="
echo "Next: copy alfredo-wake.py and .service, then enable the service."
