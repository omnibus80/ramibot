#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
MODEL_DIR="${RAMIBOT_MODEL_DIR:-$ROOT_DIR/models/gguf}"
MODEL_PATH="$MODEL_DIR/g9v3-3b-q8_0.gguf"
PART_PATH="$MODEL_PATH.part"
MODEL_URL="https://huggingface.co/RichardoC/G9v3-3B-Q8_0-GGUF/resolve/main/g9v3-3b-q8_0.gguf?download=true"
MODEL_SHA256="09bbda6bf034180c8e77e22c5415a9b7498cecf3c630bebf21cdb40e1fd3daed"

verify_model() {
    local actual
    if command -v sha256sum >/dev/null 2>&1; then
        actual="$(sha256sum "$1" | cut -d' ' -f1)"
    elif command -v shasum >/dev/null 2>&1; then
        actual="$(shasum -a 256 "$1" | cut -d' ' -f1)"
    else
        echo "[model] sha256sum or shasum is required to verify the model." >&2
        return 1
    fi
    [[ "$actual" == "$MODEL_SHA256" ]]
}

mkdir -p "$MODEL_DIR"
if [[ -f "$MODEL_PATH" ]]; then
    if verify_model "$MODEL_PATH"; then
        echo "[model] G9v3-3B Heretic Q8_0 is already downloaded and verified."
        exit 0
    fi
    echo "[model] Existing GGUF checksum is invalid; downloading a verified copy."
    rm -f "$MODEL_PATH"
fi

echo "[model] Downloading G9v3-3B Heretic Q8_0 (about 3.2 GB)..."
if command -v curl >/dev/null 2>&1; then
    curl --fail --location --retry 3 --continue-at - --output "$PART_PATH" "$MODEL_URL"
elif command -v wget >/dev/null 2>&1; then
    wget --continue --output-document="$PART_PATH" "$MODEL_URL"
else
    echo "[model] Install curl or wget, then rerun this script." >&2
    exit 1
fi

if ! verify_model "$PART_PATH"; then
    echo "[model] Downloaded file failed SHA-256 verification; removing it so the next run starts clean." >&2
    rm -f "$PART_PATH"
    exit 1
fi

mv "$PART_PATH" "$MODEL_PATH"
echo "[model] Model downloaded and verified: $MODEL_PATH"