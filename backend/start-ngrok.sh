#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${SCRIPT_DIR}/.env"
NGROK_BIN="${NGROK_BIN:-/home/codespace/.local/bin/ngrok}"

if [[ ! -f "${ENV_FILE}" ]]; then
    echo "Missing ${ENV_FILE}; copy backend/.env.example to backend/.env and fill it locally." >&2
    exit 1
fi

set -a
source "${ENV_FILE}"
set +a

: "${NGROK_AUTHTOKEN:?NGROK_AUTHTOKEN is required in backend/.env}"
: "${NGROK_DOMAIN:?NGROK_DOMAIN is required in backend/.env}"
NGROK_TARGET_PORT="${NGROK_TARGET_PORT:-5173}"

if [[ ! -x "${NGROK_BIN}" ]]; then
    echo "ngrok binary not found at ${NGROK_BIN}." >&2
    exit 1
fi

"${NGROK_BIN}" config add-authtoken "${NGROK_AUTHTOKEN}" >/dev/null
exec "${NGROK_BIN}" http --domain="${NGROK_DOMAIN}" "${NGROK_TARGET_PORT}"