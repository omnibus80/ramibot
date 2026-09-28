#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${SCRIPT_DIR}/.env"
NGROK_BIN="${NGROK_BIN:-$(command -v ngrok || true)}"
[[ -n "$NGROK_BIN" ]] || NGROK_BIN="${HOME}/.local/bin/ngrok"

if [[ ! -f "${ENV_FILE}" ]]; then
    echo "Missing ${ENV_FILE}; copy backend/.env.example to backend/.env and fill it locally." >&2
    exit 1
fi

set -a
source "${ENV_FILE}"
[[ ! -f "${SCRIPT_DIR}/ngrok.env" ]] || source "${SCRIPT_DIR}/ngrok.env"
set +a

NGROK_TARGET_PORT="${RAMIBOT_FRONTEND_PORT:-${NGROK_TARGET_PORT:-5173}}"
NGROK_API_PORT="${NGROK_API_PORT:-4040}"

if [[ ! -x "${NGROK_BIN}" ]]; then
    echo "ngrok binary not found at ${NGROK_BIN}." >&2
    exit 1
fi

if [[ -n "${NGROK_AUTHTOKEN:-}" ]]; then
    "${NGROK_BIN}" config add-authtoken "${NGROK_AUTHTOKEN}" >/dev/null
fi
if [[ -n "${NGROK_DOMAIN:-}" ]]; then
    exec "${NGROK_BIN}" http --web-addr="127.0.0.1:${NGROK_API_PORT}" --domain="${NGROK_DOMAIN}" "${NGROK_TARGET_PORT}"
fi
exec "${NGROK_BIN}" http --web-addr="127.0.0.1:${NGROK_API_PORT}" "${NGROK_TARGET_PORT}"