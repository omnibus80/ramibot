#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SERVICE_USER="${SUDO_USER:-$(id -un)}"

if [[ ! -d /run/systemd/system ]] || ! command -v systemctl >/dev/null 2>&1; then
    echo "systemd is unavailable; cannot install a persistent host service." >&2
    exit 1
fi

if [[ "$EUID" -eq 0 ]]; then
    ROOT=( )
elif command -v sudo >/dev/null 2>&1; then
    ROOT=(sudo)
else
    echo "sudo/root is required to install /etc/systemd/system/ramibot.service." >&2
    exit 1
fi

SERVICE_FILE="$(mktemp)"
trap 'rm -f "$SERVICE_FILE"' EXIT
cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=RamiBot and Osiris local intelligence app
Wants=network-online.target
After=network-online.target docker.service

[Service]
Type=simple
User=$SERVICE_USER
WorkingDirectory=$ROOT_DIR
Environment=HOME=$(getent passwd "$SERVICE_USER" | cut -d: -f6)
Environment=PATH=/usr/local/bin:/usr/bin:/bin:$HOME/.local/bin
ExecStart=/bin/bash $ROOT_DIR/start.sh
Restart=always
RestartSec=10
KillSignal=SIGINT
TimeoutStopSec=45

[Install]
WantedBy=multi-user.target
EOF

"${ROOT[@]}" install -m 0644 "$SERVICE_FILE" /etc/systemd/system/ramibot.service
"${ROOT[@]}" systemctl daemon-reload
"${ROOT[@]}" systemctl enable --now ramibot.service
echo "RamiBot is enabled at boot and will restart if its app process exits."
echo "Logs: journalctl -u ramibot -f"