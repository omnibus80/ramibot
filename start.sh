#!/usr/bin/env bash
# =============================================================================
# RamiBot — Daily startup (Linux / macOS)
# Usage: bash start.sh
# Ctrl+C stops local app processes; available Docker services keep running.
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

RED='\033[0;31m'; YELLOW='\033[1;33m'; GREEN='\033[0;32m'; CYAN='\033[0;36m'; NC='\033[0m'

info()    { echo -e "${CYAN}[ramibot]${NC} $*"; }
success() { echo -e "${GREEN}[ramibot]${NC} $*"; }
warn()    { echo -e "${YELLOW}[ramibot]${NC} $*"; }
error()   { echo -e "${RED}[ramibot]${NC} $*"; }

# ── PIDs for cleanup ──────────────────────────────────────────────────────────
BACKEND_PID=""
FRONTEND_PID=""
OSIRIS_PID=""
NGROK_PID=""
LLAMA_PID=""

cleanup() {
    trap - EXIT SIGINT SIGTERM
    echo ""
    info "Shutting down..."
    [[ -n "$BACKEND_PID" ]]  && kill "$BACKEND_PID"  2>/dev/null && info "  Backend stopped."
    [[ -n "$FRONTEND_PID" ]] && kill "$FRONTEND_PID" 2>/dev/null && info "  Frontend stopped."
    [[ -n "$OSIRIS_PID" ]] && kill "$OSIRIS_PID" 2>/dev/null && info "  Osiris stopped."
    [[ -n "$NGROK_PID" ]] && kill "$NGROK_PID" 2>/dev/null && info "  ngrok stopped."
    [[ -n "$LLAMA_PID" ]] && kill "$LLAMA_PID" 2>/dev/null && info "  GGUF server stopped."
    info "Docker containers remain running (restart: unless-stopped)."
    exit 0
}
trap cleanup SIGINT SIGTERM EXIT

# =============================================================================
# 1. Sanity checks
# =============================================================================
info "Running sanity checks..."
if [[ ! -x "backend/.venv/bin/python" || ! -f "backend/settings.json" || ! -f "backend/.env" || ! -f ".env" || ! -d "frontend/node_modules" || ! -d "osiris/node_modules" || ! -f "models/gguf/g9v3-3b-q8_0.gguf" ]]; then
    warn "First-run files are missing; running the complete installer now."
    bash install.sh
fi
success "Sanity checks passed."

set -a
source backend/.env
set +a
export PATH="$HOME/.local/bin:$PATH"
bash scripts/setup-ports.sh
source .ramibot-ports
export RAMIBOT_BACKEND_PORT RAMIBOT_FRONTEND_PORT OSIRIS_PORT GGUF_PORT NGROK_API_PORT
export OSIRIS_TARGET="http://127.0.0.1:${OSIRIS_PORT}"
success "Selected ports: backend=$RAMIBOT_BACKEND_PORT, UI=$RAMIBOT_FRONTEND_PORT, Osiris=$OSIRIS_PORT, GGUF=$GGUF_PORT."

# =============================================================================
# 2. Ensure the repository-local GGUF model is available
# =============================================================================
bash scripts/setup-gguf.sh

# =============================================================================
# 3. Ensure local GGUF server is running
# =============================================================================
LLAMA_BIN="$SCRIPT_DIR/build/llama.cpp/build/bin/llama-server"
MODEL_DIR="${RAMIBOT_MODEL_DIR:-$SCRIPT_DIR/models/gguf}"
MODEL_PATH="$MODEL_DIR/g9v3-3b-q8_0.gguf"
if [[ ! -x "$LLAMA_BIN" ]]; then
    bash scripts/setup-llama-server.sh
fi
if [[ ! -f "$MODEL_PATH" ]]; then
    bash scripts/setup-gguf.sh
fi
info "Starting native G9v3-3B Heretic Q8_0 server on port $GGUF_PORT..."
mkdir -p logs
LLAMA_GPU_ARGS=()
if [[ "${RAMIBOT_GPU_BACKEND:-auto}" == cuda || "${RAMIBOT_GPU_BACKEND:-auto}" == vulkan ]]; then
    LLAMA_GPU_ARGS=(--n-gpu-layers auto)
fi
"$LLAMA_BIN" --model "$MODEL_PATH" --alias G9v3-3B-Heretic-Q8_0 \
    --host 127.0.0.1 --port "$GGUF_PORT" --ctx-size 8192 --jinja \
    "${LLAMA_GPU_ARGS[@]}" >logs/llama-server.log 2>&1 &
LLAMA_PID=$!

# =============================================================================
# 4. Start Osiris
# =============================================================================
info "Starting Osiris on port $OSIRIS_PORT..."
(
    cd osiris
    npm run dev -- --hostname 127.0.0.1 --port "$OSIRIS_PORT"
) &
OSIRIS_PID=$!

# =============================================================================
# 5. Ensure rami-kali container is running
# =============================================================================
if command -v docker >/dev/null 2>&1 && (docker info >/dev/null 2>&1 || sudo -n docker info >/dev/null 2>&1); then
    if docker compose version >/dev/null 2>&1; then
        COMPOSE=(docker compose)
        docker info >/dev/null 2>&1 || COMPOSE=(sudo -n docker compose)
    elif command -v docker-compose >/dev/null 2>&1; then
        COMPOSE=(docker-compose)
        docker info >/dev/null 2>&1 || COMPOSE=(sudo -n docker-compose)
    else
        COMPOSE=()
    fi
    if [[ ${#COMPOSE[@]} -gt 0 ]]; then
        info "Starting optional rami-kali MCP container..."
        "${COMPOSE[@]}" -f rami-kali/docker-compose.yml up -d || warn "Kali MCP did not start; the rest of the app will remain available."
    fi
else
    if [[ "${RAMIBOT_ALLOW_NO_DOCKER:-0}" == 1 ]]; then
        warn "Docker daemon unavailable; running explicit no-Kali development mode."
    else
        error "Rami-Kali MCP requires Docker Engine and Compose. Start Docker and rerun bash start.sh."
        exit 1
    fi
fi

# =============================================================================
# 6. Start backend
# =============================================================================
BACKEND_PORT="$RAMIBOT_BACKEND_PORT"
info "Starting backend on http://localhost:${BACKEND_PORT} ..."
(
    cd backend
    source .venv/bin/activate
    python -m uvicorn main:app --reload --host 127.0.0.1 --port "$BACKEND_PORT"
) &
BACKEND_PID=$!

# =============================================================================
# 7. Start frontend
# =============================================================================
info "Starting frontend on http://localhost:${RAMIBOT_FRONTEND_PORT} ..."
(
    cd frontend
    npm run dev -- --host 127.0.0.1 --port "$RAMIBOT_FRONTEND_PORT"
) &
FRONTEND_PID=$!

# =============================================================================
# 8. Start the public ngrok tunnel
# =============================================================================
info "Starting ngrok public UI tunnel..."
bash backend/start-ngrok.sh >backend/ngrok.log 2>&1 &
NGROK_PID=$!

# =============================================================================
# 9. Wait for services and announce access URLs
# =============================================================================
wait_for_url() {
    local url="$1" label="$2" max_attempts="${3:-120}" attempt
    for attempt in $(seq 1 "$max_attempts"); do
        if curl --silent --fail "$url" >/dev/null; then
            info "$label is ready."
            return 0
        fi
        if [[ "$label" == "Osiris" ]] && ! kill -0 "$OSIRIS_PID" 2>/dev/null; then
            error "Osiris exited during startup. Review its startup output above."
            return 1
        fi
        sleep 1
    done
    error "$label did not become ready within ${max_attempts} seconds."
    return 1
}

wait_for_url "http://127.0.0.1:${GGUF_PORT}/v1/models" "Local GGUF model" 300
wait_for_url "http://127.0.0.1:${OSIRIS_PORT}/osiris/" "Osiris"
wait_for_url "http://127.0.0.1:${BACKEND_PORT}/api/health" "Backend"
wait_for_url "http://127.0.0.1:${RAMIBOT_FRONTEND_PORT}" "RamiBot UI"

PUBLIC_URL=""
if command -v ngrok >/dev/null 2>&1 || [[ -x "$HOME/.local/bin/ngrok" ]]; then
    for attempt in $(seq 1 30); do
        PUBLIC_URL="$(python3 -c 'import json,sys,urllib.request; data=json.load(urllib.request.urlopen(f"http://127.0.0.1:{sys.argv[1]}/api/tunnels", timeout=2)); print(next((t["public_url"] for t in data.get("tunnels", []) if t.get("proto") == "https"), ""))' "$NGROK_API_PORT" 2>/dev/null || true)"
        [[ -n "$PUBLIC_URL" ]] && break
        sleep 1
    done
fi

# =============================================================================
# 10. Open browser locally (best-effort)
# =============================================================================
(
    sleep 4
    if command -v xdg-open &>/dev/null; then
        xdg-open "http://127.0.0.1:${RAMIBOT_FRONTEND_PORT}" &>/dev/null || true
    elif command -v open &>/dev/null; then
        open "http://127.0.0.1:${RAMIBOT_FRONTEND_PORT}" || true
    fi
) &

success "RamiBot and Osiris are running."
echo ""
echo -e "  Local UI: ${CYAN}http://127.0.0.1:${RAMIBOT_FRONTEND_PORT}${NC}"
if [[ -n "$PUBLIC_URL" ]]; then
    echo -e "  Public UI: ${GREEN}${PUBLIC_URL}${NC}"
    echo "  Osiris is embedded inside the public RamiBot UI."
elif [[ -n "$NGROK_PID" ]]; then
    warn "ngrok did not report a public URL; inspect backend/ngrok.log and configure an ngrok account token if needed."
fi
echo ""
echo "  Press Ctrl+C to stop RamiBot, Osiris, GGUF, and ngrok. Docker containers remain running."
echo ""

# Wait for either process to exit (unexpected crash)
wait -n "$BACKEND_PID" "$FRONTEND_PID" "$OSIRIS_PID" 2>/dev/null || true
