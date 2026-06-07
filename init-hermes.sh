#!/usr/bin/env bash
# =============================================================================
# init-hermes — Clone, build, and run Hermes Agent for a project
# =============================================================================
# Usage:
#   cd ~/my-project
#   ./init-hermes.sh
#
#   Or with env vars:
#   PROVIDER=anthropic MODEL=claude-sonnet-4-20250514 ANTHROPIC_API_KEY=sk-... ./init-hermes.sh
# =============================================================================

set -euo pipefail

# Colors
ok()   { echo -e "\033[32m✔\033[0m $*"; }
info() { echo -e "\033[34mℹ\033[0m $*"; }
warn() { echo -e "\033[33m⚠\033[0m $*"; }
err()  { echo -e "\033[31m✘\033[0m $*" >&2; exit 1; }

# =============================================================================
# Detect container runtime
# =============================================================================
ENGINE=docker
if command -v podman &>/dev/null; then
    ENGINE=podman
elif command -v docker &>/dev/null; then
    ENGINE=docker
else
    err "No container runtime found (need docker or podman)"
fi

# =============================================================================
# Resolve paths
# =============================================================================
PROJECT_DIR="$(pwd)"
WRAPPER_DIR="${PROJECT_DIR}/.hermes-compose"
DATA_DIR="${PROJECT_DIR}/.hermes"

PROJECT_NAME="${PWD##*/}"
CONTAINER_NAME="hermes-${PROJECT_NAME//-/_}"

# =============================================================================
# Clone or update wrapper repo
# =============================================================================
if [[ -d "${WRAPPER_DIR}/.git" ]]; then
    info "Pulling latest hermes-compose..."
    cd "${WRAPPER_DIR}"
    ${ENGINE} compose down 2>/dev/null || true
    git pull || warn "Pull failed, continuing with existing version"
    cd "${PROJECT_DIR}"
else
    info "Cloning hermes-compose..."
    git clone https://github.com/themimi974/hermes-compose.git "${WRAPPER_DIR}"
fi

# =============================================================================
# .env setup
# =============================================================================
ENV_SRC="${PROJECT_DIR}/.env"
ENV_DEST="${DATA_DIR}/.env"

mkdir -p "${DATA_DIR}"

if [[ -f "${ENV_SRC}" ]]; then
    # .env found next to where the script was run — use it
    info "Found .env in current directory — copying to ${ENV_DEST}"
    cp -f "${ENV_SRC}" "${ENV_DEST}"

elif [[ -n "${OPENAI_API_KEY:-}${ANTHROPIC_API_KEY:-}${NVIDIA_API_KEY:-}${OPENROUTER_API_KEY:-}${GOOGLE_API_KEY:-}${OLLAMA_HOST:-}${CUSTOM_BASE_URL:-}" ]]; then
    # Keys already exported in the shell — write them out
    info "Detected exported env vars — writing to ${ENV_DEST}"
    {
        [[ -n "${PROVIDER:-}" ]]           && echo "PROVIDER=${PROVIDER}"
        [[ -n "${MODEL:-}" ]]              && echo "MODEL=${MODEL}"
        [[ -n "${OPENAI_API_KEY:-}" ]]     && echo "OPENAI_API_KEY=${OPENAI_API_KEY}"
        [[ -n "${ANTHROPIC_API_KEY:-}" ]]  && echo "ANTHROPIC_API_KEY=${ANTHROPIC_API_KEY}"
        [[ -n "${NVIDIA_API_KEY:-}" ]]     && echo "NVIDIA_API_KEY=${NVIDIA_API_KEY}"
        [[ -n "${OPENROUTER_API_KEY:-}" ]] && echo "OPENROUTER_API_KEY=${OPENROUTER_API_KEY}"
        [[ -n "${GOOGLE_API_KEY:-}" ]]     && echo "GOOGLE_API_KEY=${GOOGLE_API_KEY}"
        [[ -n "${OLLAMA_HOST:-}" ]]        && echo "OLLAMA_HOST=${OLLAMA_HOST}"
        [[ -n "${CUSTOM_BASE_URL:-}" ]]    && echo "CUSTOM_BASE_URL=${CUSTOM_BASE_URL}"
        [[ -n "${CUSTOM_API_KEY:-}" ]]     && echo "CUSTOM_API_KEY=${CUSTOM_API_KEY}"
        [[ -n "${HF_TOKEN:-}" ]]           && echo "HF_TOKEN=${HF_TOKEN}"
    } > "${ENV_DEST}"
    ok "Wrote ${ENV_DEST}"

else
    # Nothing found — open nano so the user can create a .env right here
    warn "No .env found and no env vars exported."
    info "Opening nano — fill in your keys, save with Ctrl+O then exit with Ctrl+X."
    nano "${ENV_SRC}"

    if [[ -f "${ENV_SRC}" ]]; then
        cp -f "${ENV_SRC}" "${ENV_DEST}"
        ok ".env saved and copied to ${ENV_DEST}"
    else
        err "No .env was created. Aborting."
    fi
fi

# Load .env so PROVIDER and MODEL are available for docker-compose
set -o allexport
source "${ENV_DEST}"
set +o allexport

# =============================================================================
# Build image
# =============================================================================
info "Building Docker image..."
cd "${WRAPPER_DIR}"
${ENGINE} compose build

# =============================================================================
# Remove any stale container
# =============================================================================
${ENGINE} rm -f $(${ENGINE} ps -aq --filter "name=${CONTAINER_NAME}" 2>/dev/null) 2>/dev/null || true

# =============================================================================
# Launch
# =============================================================================
info "Starting Hermes"
info "  Project   : ${PROJECT_NAME}"
info "  Container : ${CONTAINER_NAME}"
info "  Workspace : ${PROJECT_DIR}"
info "  Data dir  : ${DATA_DIR}"
info "  Provider  : ${PROVIDER:-"(from .env)"}"
info "  Model     : ${MODEL:-"(from .env)"}"

exec ${ENGINE} compose run --rm hermes
