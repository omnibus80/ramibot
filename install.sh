#!/usr/bin/env bash
# =============================================================================
# RamiBot — One-shot installer (Linux / macOS)
# Usage: bash install.sh
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

RED='\033[0;31m'; YELLOW='\033[1;33m'; GREEN='\033[0;32m'; CYAN='\033[0;36m'; NC='\033[0m'

info()    { echo -e "${CYAN}[install]${NC} $*"; }
success() { echo -e "${GREEN}[install]${NC} $*"; }
warn()    { echo -e "${YELLOW}[install]${NC} $*"; }
error()   { echo -e "${RED}[install]${NC} $*"; }

# =============================================================================
# 1. Install missing host prerequisites
# =============================================================================
info "Checking prerequisites..."
bash scripts/bootstrap-linux.sh
success "All prerequisites met."

# =============================================================================
# 2. Python virtual environment
# =============================================================================
if [[ ! -f "backend/.venv/bin/pip" ]]; then
    [[ -d "backend/.venv" ]] && { warn "backend/.venv exists but is invalid (wrong platform?) — recreating..."; rm -rf backend/.venv; }
    info "Creating Python virtual environment at backend/.venv ..."
    python3 -m venv backend/.venv
    success "Virtual environment created."
else
    info "backend/.venv already exists — skipping."
fi

# =============================================================================
# 3. Backend dependencies
# =============================================================================
info "Installing backend Python dependencies..."
backend/.venv/bin/pip install --quiet --upgrade pip
backend/.venv/bin/pip install --quiet -r backend/requirements.txt
success "Backend dependencies installed."

# =============================================================================
# 4. Frontend dependencies
# =============================================================================
info "Installing frontend npm dependencies..."
(cd frontend && npm install --silent)
success "Frontend dependencies installed."

if [[ ! -f ".env" ]]; then cp .env.example .env; fi
set -a
source .env
set +a

# =============================================================================
# 5. Osiris Node application
# =============================================================================
bash scripts/setup-osiris.sh

# =============================================================================
# 6. Repository-local GGUF model
# =============================================================================
info "Setting up the repository-local G9v3-3B Heretic Q8_0 model..."
bash scripts/setup-gguf.sh
info "Building the native llama.cpp server..."
bash scripts/setup-llama-server.sh
success "Local GGUF model is ready."

# =============================================================================
# 7. Settings files (never overwrite)
# =============================================================================
if [[ ! -f "backend/settings.json" ]]; then
    info "Copying backend/settings.example.json → backend/settings.json ..."
    cp backend/settings.example.json backend/settings.json
    warn "IMPORTANT: Edit backend/settings.json and add your API keys before starting."
else
    info "backend/settings.json already exists — skipping (your config is preserved)."
fi
if [[ ! -f "backend/.env" ]]; then
    cp backend/.env.example backend/.env
    warn "Set NGROK_AUTHTOKEN in backend/.env to enable your public ngrok URL."
fi
source .ramibot-ports 2>/dev/null || true
bash scripts/setup-ports.sh
source .ramibot-ports

# =============================================================================
# 8. Optional Kali MCP container
# =============================================================================
DOCKER=(docker)
if ! docker info >/dev/null 2>&1; then
    if sudo -n docker info >/dev/null 2>&1; then
        DOCKER=(sudo -n docker)
    else
        DOCKER=()
    fi
fi

if [[ ${#DOCKER[@]} -gt 0 ]]; then
    info "Building the optional rami-kali MCP image..."
    "${DOCKER[@]}" build -t rami-kali rami-kali/
    if "${DOCKER[@]}" compose version >/dev/null 2>&1; then
        "${DOCKER[@]}" compose -f rami-kali/docker-compose.yml up -d
    elif command -v docker-compose >/dev/null 2>&1; then
        if [[ "${DOCKER[0]}" == sudo ]]; then
            sudo -n docker-compose -f rami-kali/docker-compose.yml up -d
        else
            docker-compose -f rami-kali/docker-compose.yml up -d
        fi
    fi
else
    if [[ "${RAMIBOT_ALLOW_NO_DOCKER:-0}" == 1 ]]; then
        warn "Docker daemon unavailable; continuing in explicit no-Kali development mode."
    else
        error "Rami-Kali MCP requires Docker Engine and Compose. Start the Docker daemon and rerun bash install.sh."
        exit 1
    fi
fi

# =============================================================================
# Done
# =============================================================================
echo ""
success "============================================================"
success " RamiBot installation complete!"
success "============================================================"
echo ""
echo -e "  ${YELLOW}Next steps:${NC}"
echo "  1. Edit backend/settings.json — add your LLM API key(s)"
echo "  2. Run:  bash setup.sh   (full setup, ngrok prompt, and server start)"
echo "     Or:  bash start.sh   (start services after setup)"
echo ""
