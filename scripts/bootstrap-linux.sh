#!/usr/bin/env bash
set -euo pipefail

info() { printf '[bootstrap] %s\n' "$*"; }
error() { printf '[bootstrap] ERROR: %s\n' "$*" >&2; }

run_root() {
    if [[ "$EUID" -eq 0 ]]; then
        "$@"
    elif command -v sudo >/dev/null 2>&1; then
        sudo "$@"
    else
        error "Administrator access is required to install system packages. Run this script as root or install sudo."
        return 1
    fi
}

compose_available() {
    docker compose version >/dev/null 2>&1 || docker-compose --version >/dev/null 2>&1
}

python_available() {
    command -v python3 >/dev/null 2>&1 &&
        python3 -c 'import sys; raise SystemExit(sys.version_info < (3, 9))' >/dev/null 2>&1
}

node_major() {
    node --version 2>/dev/null | sed -E 's/^v?([0-9]+).*/\1/'
}

node_available() {
    local major
    command -v node >/dev/null 2>&1 && command -v npm >/dev/null 2>&1 || return 1
    major="$(node_major)"
    [[ "$major" =~ ^[0-9]+$ ]] && (( major >= 18 ))
}

install_packages() {
    local distro=""
    if [[ -r /etc/os-release ]]; then
        . /etc/os-release
        distro="${ID:-} ${ID_LIKE:-}"
    fi

    case "$distro" in
        *alpine*)
            run_root apk add --no-cache git python3 py3-pip py3-virtualenv nodejs npm docker docker-cli-compose curl wget ca-certificates xz build-base cmake ninja
            run_root rc-update add docker default || true
            run_root rc-service docker start || true
            ;;
        *debian*|*ubuntu*)
            run_root apt-get update -qq
            run_root apt-get install -y git python3 python3-venv python3-pip nodejs npm docker.io docker-compose curl wget ca-certificates xz-utils build-essential cmake ninja-build
            ;;
        *fedora*|*rhel*|*centos*)
            run_root dnf install -y git python3 python3-pip nodejs npm docker docker-compose curl wget ca-certificates xz gcc-c++ make cmake ninja-build
            ;;
        *arch*)
            run_root pacman -Sy --noconfirm git python nodejs npm docker docker-compose curl wget ca-certificates xz base-devel cmake ninja
            ;;
        *)
            error "Unsupported Linux package manager. Install Python 3.9+, Node.js 18+ with npm, Docker Compose, curl, and ngrok, then rerun."
            return 1
            ;;
    esac

    if command -v systemctl >/dev/null 2>&1; then
        run_root systemctl enable --now docker || true
    elif command -v service >/dev/null 2>&1; then
        run_root service docker start || true
    fi

    if ! compose_available; then
        case "$distro" in
            *debian*|*ubuntu*)
                run_root apt-get install -y docker-compose-plugin || run_root apt-get install -y docker-compose || true
                ;;
            *fedora*|*rhel*|*centos*)
                run_root dnf install -y docker-compose-plugin || run_root dnf install -y docker-compose || true
                ;;
        esac
    fi
}

install_node_runtime() {
    local arch node_arch version archive temp_dir expected actual install_dir
    arch="$(uname -m)"
    case "$arch" in
        x86_64|amd64) node_arch="x64" ;;
        aarch64|arm64) node_arch="arm64" ;;
        *) error "Node.js 18+ is missing and automatic runtime setup does not support architecture $arch."; return 1 ;;
    esac
    if grep -qi alpine /etc/os-release 2>/dev/null; then
        run_root apk add --no-cache --upgrade nodejs npm
        return 0
    fi

    version="v22.15.0"
    archive="node-${version}-linux-${node_arch}.tar.xz"
    temp_dir="$(mktemp -d)"
    trap 'rm -rf "$temp_dir"' RETURN
    curl --fail --location --retry 3 "https://nodejs.org/dist/${version}/${archive}" --output "$temp_dir/$archive"
    curl --fail --location --retry 3 "https://nodejs.org/dist/${version}/SHASUMS256.txt" --output "$temp_dir/SHASUMS256.txt"
    expected="$(awk -v file="$archive" '$2 == file { print $1; exit }' "$temp_dir/SHASUMS256.txt")"
    actual="$(sha256sum "$temp_dir/$archive" | cut -d' ' -f1)"
    if [[ -z "$expected" || "$actual" != "$expected" ]]; then
        error "Node.js archive failed SHA-256 verification."
        return 1
    fi

    tar -xJf "$temp_dir/$archive" -C "$temp_dir"
    install_dir="/usr/local/lib/nodejs/node-${version}-linux-${node_arch}"
    run_root mkdir -p /usr/local/lib/nodejs /usr/local/bin
    run_root cp -a "$temp_dir/node-${version}-linux-${node_arch}" "$install_dir"
    run_root ln -sfn "$install_dir/bin/node" /usr/local/bin/node
    run_root ln -sfn "$install_dir/bin/npm" /usr/local/bin/npm
    run_root ln -sfn "$install_dir/bin/npx" /usr/local/bin/npx
    export PATH="/usr/local/bin:$PATH"
}

install_ngrok() {
    local ngrok_arch temp_dir
    command -v ngrok >/dev/null 2>&1 && return 0
    [[ -x "$HOME/.local/bin/ngrok" ]] && { export PATH="$HOME/.local/bin:$PATH"; return 0; }

    case "$(uname -m)" in
        x86_64|amd64) ngrok_arch="amd64" ;;
        aarch64|arm64) ngrok_arch="arm64" ;;
        *) error "Automatic ngrok setup does not support architecture $(uname -m)."; return 1 ;;
    esac
    temp_dir="$(mktemp -d)"
    trap 'rm -rf "$temp_dir"' RETURN
    curl --fail --location --retry 3 "https://bin.equinox.io/c/bNyj1mQVY4c/ngrok-v3-stable-linux-${ngrok_arch}.tgz" --output "$temp_dir/ngrok.tgz"
    mkdir -p "$HOME/.local/bin"
    tar -xzf "$temp_dir/ngrok.tgz" -C "$HOME/.local/bin" ngrok
    chmod 0755 "$HOME/.local/bin/ngrok"
    export PATH="$HOME/.local/bin:$PATH"
}

if [[ "$(uname -s)" != Linux ]]; then
    info "Non-Linux host detected; Linux package bootstrap skipped."
    exit 0
fi

if ! python_available || ! node_available || ! command -v docker >/dev/null 2>&1 || ! compose_available || ! command -v curl >/dev/null 2>&1; then
    info "Installing missing system prerequisites with the host package manager..."
    install_packages
fi

if ! node_available; then
    info "Installing the verified Node.js 22 runtime..."
    install_node_runtime
fi

if ! python_available; then
    error "Python 3.9+ is still unavailable after package installation."
    exit 1
fi
if ! node_available; then
    error "Node.js 18+ with npm is still unavailable after package installation."
    exit 1
fi
if ! command -v docker >/dev/null 2>&1 || ! compose_available; then
    error "Docker and Docker Compose are still unavailable after package installation."
    [[ "${RAMIBOT_ALLOW_NO_DOCKER:-0}" == 1 ]] || exit 1
    info "Continuing without Docker; Kali MCP will be unavailable in this environment."
fi
if command -v docker >/dev/null 2>&1 && ! docker info >/dev/null 2>&1 && ! run_root docker info >/dev/null 2>&1; then
    error "Docker was installed but its daemon is not reachable. Start the Docker service and rerun."
    [[ "${RAMIBOT_ALLOW_NO_DOCKER:-0}" == 1 ]] || exit 1
    info "Continuing without Docker; Kali MCP will be unavailable in this environment."
fi

install_ngrok
info "Python, Node.js/npm, Docker/Compose, curl, and ngrok are ready."