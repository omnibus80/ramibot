#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PORT_FILE="${RAMIBOT_PORT_FILE:-$ROOT_DIR/.ramibot-ports}"

port_available() {
    python3 - "$1" <<'PY'
import socket
import sys

sock = socket.socket()
try:
    sock.bind(("127.0.0.1", int(sys.argv[1])))
except OSError:
    raise SystemExit(1)
finally:
    sock.close()
PY
}

choose_port() {
    local preferred="$1" candidate
    for ((candidate = preferred; candidate <= 65535 && candidate < preferred + 1000; candidate++)); do
        if port_available "$candidate" && ! printf '%s\n' "${SELECTED_PORTS[@]}" | grep -qx "$candidate"; then
            SELECTED_PORTS+=("$candidate")
            SELECTED_PORT="$candidate"
            return 0
        fi
    done
    echo "No free port found starting at $preferred." >&2
    return 1
}

declare -a SELECTED_PORTS=()
if [[ -f "$PORT_FILE" ]]; then
    source "$PORT_FILE"
fi

choose_port "${RAMIBOT_BACKEND_PORT:-8001}"
BACKEND_PORT="$SELECTED_PORT"
choose_port "${RAMIBOT_FRONTEND_PORT:-5173}"
FRONTEND_PORT="$SELECTED_PORT"
choose_port "${OSIRIS_PORT:-3000}"
OSIRIS_PORT="$SELECTED_PORT"
choose_port "${GGUF_PORT:-1234}"
GGUF_PORT="$SELECTED_PORT"
choose_port "${NGROK_API_PORT:-4040}"
NGROK_API_PORT="$SELECTED_PORT"

TEMP_PORT_FILE="$PORT_FILE.tmp"
{
    printf 'RAMIBOT_BACKEND_PORT=%q\n' "$BACKEND_PORT"
    printf 'RAMIBOT_FRONTEND_PORT=%q\n' "$FRONTEND_PORT"
    printf 'OSIRIS_PORT=%q\n' "$OSIRIS_PORT"
    printf 'GGUF_PORT=%q\n' "$GGUF_PORT"
    printf 'NGROK_API_PORT=%q\n' "$NGROK_API_PORT"
} > "$TEMP_PORT_FILE"
mv "$TEMP_PORT_FILE" "$PORT_FILE"

if [[ -f "$ROOT_DIR/backend/.env" ]]; then
    python3 - "$ROOT_DIR/backend/.env" "$FRONTEND_PORT" "$OSIRIS_PORT" "$NGROK_API_PORT" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
values = {
    "NGROK_TARGET_PORT": sys.argv[2],
    "OSIRIS_TARGET": f"http://127.0.0.1:{sys.argv[3]}",
    "NGROK_API_PORT": sys.argv[4],
}
lines = path.read_text().splitlines()
keys = set(values)
lines = [line for line in lines if line.partition("=")[0] not in keys]
lines.extend(f"{key}={value}" for key, value in values.items())
path.write_text("\n".join(lines) + "\n")
PY
fi

if [[ -f "$ROOT_DIR/.env" ]]; then
    python3 - "$ROOT_DIR/.env" "$OSIRIS_PORT" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
lines = [line for line in path.read_text().splitlines() if not line.startswith("OSIRIS_PORT=")]
lines.append(f"OSIRIS_PORT={sys.argv[2]}")
path.write_text("\n".join(lines) + "\n")
PY
fi

printf 'Selected service ports:\nBackend=%s\nFrontend=%s\nOsiris=%s\nGGUF=%s\nNgrok API=%s\n' \
    "$BACKEND_PORT" "$FRONTEND_PORT" "$OSIRIS_PORT" "$GGUF_PORT" "$NGROK_API_PORT"

if [[ -f "$ROOT_DIR/backend/settings.json" ]]; then
    python3 - "$ROOT_DIR/backend/settings.json" "$GGUF_PORT" <<'PY'
import json
import sys
from pathlib import Path

settings_path = Path(sys.argv[1])
settings = json.loads(settings_path.read_text())
lmstudio = settings.setdefault("lmstudio", {})
base_url = lmstudio.get("base_url", "")
if not base_url or "localhost" in base_url or "127.0.0.1" in base_url or "ngrok-free.dev" in base_url:
    lmstudio["base_url"] = f"http://127.0.0.1:{sys.argv[2]}"
settings_path.write_text(json.dumps(settings, indent=2) + "\n")
PY
fi