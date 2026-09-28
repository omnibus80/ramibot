#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
OSIRIS_DIR="$ROOT_DIR/osiris"
OSIRIS_REPOSITORY="https://github.com/simplifaisoul/osiris.git"

if [[ ! -f "$ROOT_DIR/.env" ]]; then
    cp "$ROOT_DIR/.env.example" "$ROOT_DIR/.env"
fi

if [[ ! -d "$OSIRIS_DIR/.git" ]]; then
    if [[ -e "$OSIRIS_DIR" ]]; then
        echo "[osiris] $OSIRIS_DIR exists but is not a Git checkout; refusing to overwrite it." >&2
        exit 1
    fi
    echo "[osiris] Cloning the official Osiris application..."
    git clone --depth 1 "$OSIRIS_REPOSITORY" "$OSIRIS_DIR"
fi

node --input-type=commonjs -e '
const fs = require("node:fs")
const configPath = process.argv[1]
const config = fs.readFileSync(configPath, "utf8")
if (!config.includes(`basePath: "/osiris"`)) {
    const declaration = "const nextConfig: NextConfig = {"
    if (config.split(declaration).length !== 2) throw new Error("Unexpected Osiris Next.js config; refusing to patch")
    fs.writeFileSync(configPath, config.replace(declaration, `${declaration}\n  basePath: "/osiris",`))
}
' "$OSIRIS_DIR/next.config.ts"

if [[ ! -f "$OSIRIS_DIR/.env" ]]; then
    cp "$ROOT_DIR/.env" "$OSIRIS_DIR/.env"
fi

echo "[osiris] Installing the Osiris web application dependencies..."
(cd "$OSIRIS_DIR" && npm install --silent)
echo "[osiris] Osiris is ready to run on localhost:3000."