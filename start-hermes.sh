#!/usr/bin/env bash
set -euo pipefail

# ═══════════════════════════════════════════════════════════════════
# start-hermes - One-shot Hermes Agent run
# ═══════════════════════════════════════════════════════════════════

ok()   { echo -e "\033[32m✔\033[0m $*"; }
info() { echo -e "\033[34mℹ\033[0m $*"; }
err()  { echo -e "\033[31m✘\033[0m $*"; exit 1; }

# --- Detect container runtime ---
if command -v podman &>/dev/null; then
    ENGINE=podman
elif command -v docker &>/dev/null; then
    ENGINE=docker
else
    err "No container runtime found (need docker or podman)"
fi

# --- Find compose file ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE_FILE="$SCRIPT_DIR/docker-compose.yml"
if [[ ! -f "$COMPOSE_FILE" ]]; then
    err "docker-compose.yml not found in $SCRIPT_DIR"
fi

# --- Dynamic container name from project dir ---
PROJECT_NAME="${PWD##*/}"
CONTAINER_NAME="hermes-${PROJECT_NAME//-/}"
info "Using $ENGINE, project: $PROJECT_NAME"

# --- Ensure data directory exists (sibling to wrapper) ---
DATA_DIR="$(cd "$SCRIPT_DIR" >/dev/null 2>&1 && cd .. && pwd)/.hermes"
if [[ ! -d "$DATA_DIR" ]]; then
    mkdir -p "$DATA_DIR"
    info "Created data directory: $DATA_DIR"
fi

# --- Validate API key ---
if [[ -z "${NVIDIA_API_KEY:-}" ]]; then
    err "NVIDIA_API_KEY is not set."
fi

# --- Cleanup old container ---
$ENGINE rm -f "$($ENGINE ps -aq --filter "name=$CONTAINER_NAME")" 2>/dev/null || true

# --- Run ---
cd "$SCRIPT_DIR"
$ENGINE compose run --rm hermes
