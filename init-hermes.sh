#!/usr/bin/env bash
# =============================================================================
# init-hermes — Clone, build, and run Hermes Agent for a project
# =============================================================================
# Usage:
#   cd ~/my-project
#   ./init-hermes.sh
#
#   With exported vars:
#   PROVIDER=anthropic MODEL=claude-sonnet-4-20250514 ANTHROPIC_API_KEY=sk-... ./init-hermes.sh
#
#   Custom OpenAI-compatible endpoint:
#   PROVIDER=openai OPENAI_BASE_URL=http://192.168.1.223:8080/v1 OPENAI_API_KEY=none ./init-hermes.sh
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
# .env setup (Sudo-free: directly using the user-owned wrapper directory)
# =============================================================================
ENV_SRC="${PROJECT_DIR}/.env"
ENV_DEST="${WRAPPER_DIR}/.env"

# Ensure the data directory exists before Docker runs so it inherits user ownership
mkdir -p "${DATA_DIR}"

if [[ -f "${ENV_SRC}" ]]; then
    # .env found in current directory — use it
    info "Found .env in current directory — copying to ${ENV_DEST}"
    cp -f "${ENV_SRC}" "${ENV_DEST}"

elif [[ -n "${OPENAI_API_KEY:-}${OPENAI_BASE_URL:-}${ANTHROPIC_API_KEY:-}${NVIDIA_API_KEY:-}${OPENROUTER_API_KEY:-}${GOOGLE_API_KEY:-}${GEMINI_API_KEY:-}${OLLAMA_HOST:-}${OLLAMA_BASE_URL:-}${DEEPSEEK_API_KEY:-}${MISTRAL_API_KEY:-}${XAI_API_KEY:-}${HF_TOKEN:-}" ]]; then
    # Keys already exported in the shell — write them out
    info "Detected exported env vars — writing to ${ENV_DEST}"
    {
        [[ -n "${PROVIDER:-}" ]]            && echo "PROVIDER=${PROVIDER}"
        [[ -n "${MODEL:-}" ]]               && echo "MODEL=${MODEL}"
        # OpenAI / custom compatible
        [[ -n "${OPENAI_API_KEY:-}" ]]      && echo "OPENAI_API_KEY=${OPENAI_API_KEY}"
        [[ -n "${OPENAI_BASE_URL:-}" ]]     && echo "OPENAI_BASE_URL=${OPENAI_BASE_URL}"
        # Anthropic
        [[ -n "${ANTHROPIC_API_KEY:-}" ]]   && echo "ANTHROPIC_API_KEY=${ANTHROPIC_API_KEY}"
        [[ -n "${ANTHROPIC_BASE_URL:-}" ]]  && echo "ANTHROPIC_BASE_URL=${ANTHROPIC_BASE_URL}"
        # NVIDIA
        [[ -n "${NVIDIA_API_KEY:-}" ]]      && echo "NVIDIA_API_KEY=${NVIDIA_API_KEY}"
        [[ -n "${NVIDIA_BASE_URL:-}" ]]     && echo "NVIDIA_BASE_URL=${NVIDIA_BASE_URL}"
        # OpenRouter
        [[ -n "${OPENROUTER_API_KEY:-}" ]]  && echo "OPENROUTER_API_KEY=${OPENROUTER_API_KEY}"
        [[ -n "${OPENROUTER_BASE_URL:-}" ]] && echo "OPENROUTER_BASE_URL=${OPENROUTER_BASE_URL}"
        # Google / Gemini
        [[ -n "${GOOGLE_API_KEY:-}" ]]      && echo "GOOGLE_API_KEY=${GOOGLE_API_KEY}"
        [[ -n "${GEMINI_API_KEY:-}" ]]      && echo "GEMINI_API_KEY=${GEMINI_API_KEY}"
        # Ollama
        [[ -n "${OLLAMA_HOST:-}" ]]         && echo "OLLAMA_HOST=${OLLAMA_HOST}"
        [[ -n "${OLLAMA_BASE_URL:-}" ]]     && echo "OLLAMA_BASE_URL=${OLLAMA_BASE_URL}"
        [[ -n "${OLLAMA_API_KEY:-}" ]]      && echo "OLLAMA_API_KEY=${OLLAMA_API_KEY}"
        # LM Studio
        [[ -n "${LM_API_KEY:-}" ]]          && echo "LM_API_KEY=${LM_API_KEY}"
        [[ -n "${LM_BASE_URL:-}" ]]         && echo "LM_BASE_URL=${LM_BASE_URL}"
        # DeepSeek
        [[ -n "${DEEPSEEK_API_KEY:-}" ]]    && echo "DEEPSEEK_API_KEY=${DEEPSEEK_API_KEY}"
        [[ -n "${DEEPSEEK_BASE_URL:-}" ]]   && echo "DEEPSEEK_BASE_URL=${DEEPSEEK_BASE_URL}"
        # Mistral
        [[ -n "${MISTRAL_API_KEY:-}" ]]     && echo "MISTRAL_API_KEY=${MISTRAL_API_KEY}"
        # xAI / Grok
        [[ -n "${XAI_API_KEY:-}" ]]         && echo "XAI_API_KEY=${XAI_API_KEY}"
        [[ -n "${XAI_BASE_URL:-}" ]]        && echo "XAI_BASE_URL=${XAI_BASE_URL}"
        # HuggingFace
        [[ -n "${HF_TOKEN:-}" ]]            && echo "HF_TOKEN=${HF_TOKEN}"
        [[ -n "${HF_BASE_URL:-}" ]]         && echo "HF_BASE_URL=${HF_BASE_URL}"
        # Groq
        [[ -n "${GROQ_API_KEY:-}" ]]        && echo "GROQ_API_KEY=${GROQ_API_KEY}"
        # Tool APIs
        [[ -n "${TAVILY_API_KEY:-}" ]]      && echo "TAVILY_API_KEY=${TAVILY_API_KEY}"
        [[ -n "${FIRECRAWL_API_KEY:-}" ]]   && echo "FIRECRAWL_API_KEY=${FIRECRAWL_API_KEY}"
        [[ -n "${EXA_API_KEY:-}" ]]         && echo "EXA_API_KEY=${EXA_API_KEY}"
    } > "${ENV_DEST}"
    ok "Wrote ${ENV_DEST}"

else
    # Nothing found — create the file first, then open nano
    warn "No .env found and no env vars exported."
    info "Opening nano — fill in your keys, save with Ctrl+O then exit with Ctrl+X."
    touch "${ENV_SRC}"
    nano "${ENV_SRC}"

    if [[ -s "${ENV_SRC}" ]]; then
        cp -f "${ENV_SRC}" "${ENV_DEST}"
        ok ".env saved and copied to ${ENV_DEST}"
    else
        err "No .env content was written. Aborting."
    fi
fi

# Load .env so PROVIDER and MODEL are available for docker-compose
set -o allexport
# shellcheck source=/dev/null
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
