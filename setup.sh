#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT_DIR"

if [[ "$(uname -s)" != Linux ]]; then
    echo "This one-paste setup currently supports Linux hosts." >&2
    exit 1
fi

echo "RamiBot quick setup will install Python, Node/npm, Git, ngrok, the G9v3 GGUF, and Osiris."
echo "Rami-Kali MCP requires a working Docker Engine/Compose daemon; setup stops if it is unavailable."
echo
bash install.sh

USE_SYSTEMD=0
if [[ -d /run/systemd/system ]] && command -v systemctl >/dev/null 2>&1; then
    read -r -p "Install and enable RamiBot as a persistent systemd service? [Y/n] " SERVICE_ANSWER
    if [[ ! "$SERVICE_ANSWER" =~ ^[Nn] ]]; then USE_SYSTEMD=1; fi
else
    echo "No systemd host detected; RamiBot will run in this terminal session."
fi

echo
echo "ngrok account setup (leave token blank for local-only / saved ngrok login)."
read -r -s -p "Paste ngrok authtoken: " NGROK_TOKEN
printf '\n'
read -r -p "Reserved ngrok domain (blank for an assigned public URL): " NGROK_DOMAIN

export NGROK_TOKEN_VALUE="$NGROK_TOKEN"
export NGROK_DOMAIN_VALUE="$NGROK_DOMAIN"
python3 - "$ROOT_DIR/backend/.env" <<'PY'
from pathlib import Path
import os
import sys

path = Path(sys.argv[1])
updates = {
    "NGROK_DOMAIN": os.environ.get("NGROK_DOMAIN_VALUE", ""),
}
token = os.environ.get("NGROK_TOKEN_VALUE", "")
if token:
    updates["NGROK_AUTHTOKEN"] = token
lines = path.read_text().splitlines() if path.exists() else []
keys = set(updates)
lines = [line for line in lines if line.partition("=")[0] not in keys]
lines.extend(f"{key}={value}" for key, value in updates.items())
path.write_text("\n".join(lines) + "\n")
path.chmod(0o600)
PY
unset NGROK_TOKEN NGROK_DOMAIN NGROK_TOKEN_VALUE NGROK_DOMAIN_VALUE

bash scripts/setup-ports.sh

if (( USE_SYSTEMD )); then
    bash scripts/install-systemd.sh
    source .ramibot-ports
    for attempt in $(seq 1 180); do
        if curl --silent --fail "http://127.0.0.1:${RAMIBOT_FRONTEND_PORT}" >/dev/null; then break; fi
        sleep 1
    done
    if ! curl --silent --fail "http://127.0.0.1:${RAMIBOT_FRONTEND_PORT}" >/dev/null; then
        echo "RamiBot did not become ready. Check: sudo journalctl -u ramibot -n 100" >&2
        exit 1
    fi
    PUBLIC_URL="$(python3 - "$NGROK_API_PORT" <<'PY'
import json
import sys
import urllib.request
try:
    data = json.load(urllib.request.urlopen(f"http://127.0.0.1:{sys.argv[1]}/api/tunnels", timeout=2))
    print(next((t["public_url"] for t in data.get("tunnels", []) if t.get("proto") == "https"), ""))
except Exception:
    print("")
PY
    )"
    echo
    echo "RamiBot systemd service is enabled."
    echo "Local UI: http://127.0.0.1:${RAMIBOT_FRONTEND_PORT}"
    [[ -n "$PUBLIC_URL" ]] && echo "Public UI: $PUBLIC_URL" || echo "Public URL unavailable; check: sudo journalctl -u ramibot -n 100"
    echo "Osiris is embedded in the RamiBot UI."
else
    exec bash start.sh
fi