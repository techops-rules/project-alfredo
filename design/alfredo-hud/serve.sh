#!/usr/bin/env bash
# Serve the alfredo HUD prototype locally and open it in the browser.
# Usage: ./serve.sh [port]
set -euo pipefail
cd "$(dirname "$0")"
PORT="${1:-8000}"
URL="http://localhost:${PORT}/"
echo "alfredo HUD → ${URL}"
# open in default browser after a brief delay (backgrounded)
( sleep 0.5 && command -v open >/dev/null && open "$URL" ) &
exec python3 -m http.server "$PORT"
