#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
LLAMA_DIR="$ROOT_DIR/build/llama.cpp"
LLAMA_BIN="$LLAMA_DIR/build/bin/llama-server"
GPU_BACKEND="${RAMIBOT_GPU_BACKEND:-auto}"

if [[ ! -x "$LLAMA_BIN" ]]; then
    if [[ ! -d "$LLAMA_DIR/.git" ]]; then
        mkdir -p "$(dirname "$LLAMA_DIR")"
        git clone --depth 1 https://github.com/ggml-org/llama.cpp.git "$LLAMA_DIR"
    else
        git -C "$LLAMA_DIR" pull --ff-only
    fi
    CMAKE_ARGS=(
        -DCMAKE_BUILD_TYPE=Release
        -DGGML_NATIVE=ON
        -DLLAMA_BUILD_SERVER=ON
        -DLLAMA_BUILD_TESTS=OFF
        -DLLAMA_BUILD_EXAMPLES=OFF
        -DLLAMA_CURL=OFF
    )
    if [[ "$GPU_BACKEND" == cuda ]] && command -v nvcc >/dev/null 2>&1; then
        CMAKE_ARGS+=(-DGGML_CUDA=ON)
    elif [[ "$GPU_BACKEND" == vulkan ]] && command -v vulkaninfo >/dev/null 2>&1; then
        CMAKE_ARGS+=(-DGGML_VULKAN=ON)
    fi

    cmake -S "$LLAMA_DIR" -B "$LLAMA_DIR/build" \
        "${CMAKE_ARGS[@]}"
    cmake --build "$LLAMA_DIR/build" --target llama-server --parallel "${RAMIBOT_BUILD_JOBS:-2}"
fi

echo "[llama.cpp] Native server ready: $LLAMA_BIN"