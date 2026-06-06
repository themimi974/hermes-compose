#!/usr/bin/env bash
# =============================================================================
# init-hermes — Clone, build, and run Hermes Agent for a project
# =============================================================================
# Usage:
#   cd ~/my-project
#   PROVIDER=ollama MODEL=llama3.1 init-hermes
#   PROVIDER=openrouter MODEL=openai/gpt-4o init-hermes
#   PROVIDER=nvidia MODEL=meta/llama-3.1-70b-instruct NVIDIA_API_KEY=nvapi-... init-hermes
#   # or interactive:
#   init-hermes   # prompts for provider choice
# =============================================================================

set -euo pipefail

# Colors
ok()   { echo -e "\033[32m✔\033[0m $*"; }
info() { echo -e "\033[34mℹ\033[0m $*"; }
warn() { echo -e "\033[33m⚠\033[0m $*"; }
err()  { echo -e "\033[31m✘\033[0m $*" >&2; exit 1; }

# Symlink resolution
SOURCE="${BASH_SOURCE[0]}"
while [ -h "$SOURCE" ]; do
    DIR="$(cd -P "$(dirname "$SOURCE")" >/dev/null 2>&1 && pwd)"
    SOURCE="$(readlink "$SOURCE")"
    [[ "$SOURCE" != /* ]] && SOURCE="$DIR/$SOURCE"
done
SCRIPT_DIR="$(cd -P "$(dirname "$SOURCE")" >/dev/null 2>&1 && pwd)"

# Detect container runtime
ENGINE=docker
if command -v podman &>/dev/null; then
    ENGINE=podman
elif command -v docker &>/dev/null; then
    ENGINE=docker
else
    err "No container runtime found (need docker or podman)"
fi

# Resolve paths
PROJECT_DIR="$(pwd)"
WRAPPER_DIR="${PROJECT_DIR}/.hermes-compose"
DATA_DIR="${PROJECT_DIR}/.hermes"
COMPOSE_FILE="${WRAPPER_DIR}/docker-compose.yml"

# Dynamic container name
PROJECT_NAME="${PWD##*/}"
CONTAINER_NAME="hermes-${PROJECT_NAME//-/_}"

# Clone or pull wrapper
if [[ -d "${WRAPPER_DIR}/.git" ]]; then
    info "Wrapper already exists at ${WRAPPER_DIR} — pulling updates"
    cd "${WRAPPER_DIR}"
    ${ENGINE} compose down 2>/dev/null || true
    git pull || warn "Pull failed, continuing with existing"
elif [[ -d "${WRAPPER_DIR}" ]]; then
    info "Wrapper directory exists without git — using existing"
else
    info "Cloning hermes-compose to ${WRAPPER_DIR}"
    git clone https://github.com/themimi974/hermes-compose.git "${WRAPPER_DIR}"
fi

# Ensure data directory exists
if [[ ! -d "${DATA_DIR}" ]]; then
    mkdir -p "${DATA_DIR}"
    ok "Created data directory: ${DATA_DIR}"
fi

# =============================================================================
# Provider selection
# =============================================================================
SUPPORTED_PROVIDERS="nvidia openai anthropic openrouter gemini ollama lmstudio local custom"

# If PROVIDER is already set, just validate it
if [[ -n "${PROVIDER:-}" ]]; then
    if ! echo "${SUPPORTED_PROVIDERS}" | grep -qw "${PROVIDER}"; then
        err "Unsupported provider '${PROVIDER}'. Supported: ${SUPPORTED_PROVIDERS}"
    fi
else
    PROVIDER=""
fi

# Interactive provider selection if not set
if [[ -z "${PROVIDER}" ]] && [[ -t 0 ]]; then
    echo ""
    info "=== Hermes Agent Provider Setup ==="
    echo ""
    echo "  1) nvidia     - NVIDIA NIM (cloud, free tier available)"
    echo "  2) openai     - OpenAI API (paid)"
    echo "  3) anthropic  - Anthropic API (paid)"
    echo "  4) openrouter - OpenRouter (multi-provider, paid)"
    echo "  5) gemini     - Google Gemini (free tier available)"
    echo "  6) ollama     - Local Ollama instance"
    echo "  7) lmstudio   - Local LM Studio"
    echo "  8) local      - Local via llama.cpp"
    echo "  9) custom     - Custom OpenAI-compatible endpoint"
    echo ""
    read -p "Choose provider (1-9 or name): " provider_input

    case "${provider_input}" in
        1) PROVIDER="nvidia" ;;
        2) PROVIDER="openai" ;;
        3) PROVIDER="anthropic" ;;
        4) PROVIDER="openrouter" ;;
        5) PROVIDER="gemini" ;;
        6) PROVIDER="ollama" ;;
        7) PROVIDER="lmstudio" ;;
        8) PROVIDER="local" ;;
        9) PROVIDER="custom" ;;
        nvidia|openai|anthropic|openrouter|gemini|ollama|lmstudio|local|custom)
            PROVIDER="${provider_input}" ;;
        *)
            err "Invalid choice. Supported: ${SUPPORTED_PROVIDERS}" ;;
    esac
fi

if [[ -z "${PROVIDER}" ]]; then
    err "No provider selected. Set PROVIDER env var or run interactively."
fi

info "Using provider: ${PROVIDER}"

# =============================================================================
# Model selection
# =============================================================================
if [[ -z "${MODEL:-}" ]]; then
    # Set default based on provider
    case "${PROVIDER}" in
        nvidia)     MODEL="meta/llama-3.1-70b-instruct" ;;
        openai)     MODEL="gpt-4o" ;;
        anthropic)  MODEL="claude-sonnet-4-20250514" ;;
        openrouter) MODEL="meta-llama/llama-3.1-70b-instruct" ;;
        gemini)     MODEL="gemini-2.0-flash" ;;
        ollama)     MODEL="llama3.1" ;;
        lmstudio)   MODEL="local-model" ;;
        local)      MODEL="local" ;;
        custom)     MODEL="gpt-4o" ;;
    esac

    if [[ -t 0 ]]; then
        read -p "Model name [${MODEL}]: " model_input
        [[ -n "${model_input}" ]] && MODEL="${model_input}"
    fi
fi

info "Using model: ${MODEL}"

# =============================================================================
# API key setup
# =============================================================================
# Required keys per provider
REQUIRED_KEYS=""
case "${PROVIDER}" in
    nvidia)     REQUIRED_KEYS="NVIDIA_API_KEY" ;;
    openai)     REQUIRED_KEYS="OPENAI_API_KEY" ;;
    anthropic)  REQUIRED_KEYS="ANTHROPIC_API_KEY" ;;
    openrouter) REQUIRED_KEYS="OPENROUTER_API_KEY" ;;
    gemini)     REQUIRED_KEYS="GOOGLE_API_KEY" ;;
    ollama|lmstudio|local|custom)
        REQUIRED_KEYS="" ;;
esac

# Check if required keys are set
if [[ -n "${REQUIRED_KEYS}" ]]; then
    for key in ${REQUIRED_KEYS}; do
        if [[ -z "${!key:-}" ]]; then
            info "${key} is not set."
            if [[ -t 0 ]]; then
                # Check if .env has it
                if [[ -f "${DATA_DIR}/.env" ]] && grep -q "^${key}=" "${DATA_DIR}/.env" 2>/dev/null; then
                    info "Found ${key} in .env file"
                else
                    read -p "Enter ${key} (or leave empty to skip): " key_value
                    if [[ -n "${key_value}" ]]; then
                        export "${key}=${key_value}"
                    fi
                fi
            fi
        fi
    done
fi

# Ollama-specific host setup
if [[ "${PROVIDER}" == "ollama" ]] && [[ -z "${OLLAMA_HOST:-}" ]]; then
    if [[ -t 0 ]]; then
        read -p "Ollama host [http://host.docker.internal:11434]: " ollama_host
        [[ -n "${ollama_host}" ]] && export OLLAMA_HOST="${ollama_host}"
    else
        export OLLAMA_HOST="http://host.docker.internal:11434"
    fi
fi

# Custom endpoint setup
if [[ "${PROVIDER}" == "custom" ]]; then
    if [[ -z "${CUSTOM_BASE_URL:-}" ]]; then
        if [[ -t 0 ]]; then
            read -p "Custom API base URL [http://localhost:8000/v1]: " custom_url
            [[ -n "${custom_url}" ]] && export CUSTOM_BASE_URL="${custom_url}"
        else
            export CUSTOM_BASE_URL="http://localhost:8000/v1"
        fi
    fi
fi

# =============================================================================
# SSH key setup (optional)
# =============================================================================
SSH_VOLUME=""
if [[ -n "${HERMES_SSH:-}" ]]; then
    if [[ "${HERMES_SSH}" == "none" ]]; then
        SSH_VOLUME=""
    elif [[ -d "${HERMES_SSH}" ]]; then
        SSH_VOLUME="${HERMES_SSH}:/root/.ssh:ro,z"
    elif [[ -f "${HERMES_SSH}" ]]; then
        SSH_VOLUME="${HERMES_SSH}:/root/.ssh/id_rsa:ro,z"
        SSH_VOLUME="${SSH_VOLUME},/root/.ssh:/root/.ssh:rw"
    fi

    if [[ -n "${SSH_VOLUME}" ]]; then
        info "Injecting SSH volume: ${SSH_VOLUME}"
        if grep -q "^      - ../.hermes:/opt/data:rw,z" "$COMPOSE_FILE"; then
            sed -i "/^      - \.\.\/\.hermes:\/opt\/data:rw,z/a\\      - ${SSH_VOLUME}" "$COMPOSE_FILE"
        fi
    fi
fi

# =============================================================================
# Ensure .env exists with correct provider keys
# =============================================================================
if [[ ! -f "${DATA_DIR}/.env" ]]; then
    if [[ -f "${WRAPPER_DIR}/.env.example" ]]; then
        cp "${WRAPPER_DIR}/.env.example" "${DATA_DIR}/.env"
    fi
    info "Created .env from template"
else
    info ".env already exists — using existing"
fi

# Write provider-specific keys to .env
{
    # Write required keys
    if [[ -n "${NVIDIA_API_KEY:-}" ]]; then
        sed -i "s|^NVIDIA_API_KEY=.*|NVIDIA_API_KEY=${NVIDIA_API_KEY}|" "${DATA_DIR}/.env" 2>/dev/null || echo "NVIDIA_API_KEY=${NVIDIA_API_KEY}" >> "${DATA_DIR}/.env"
    fi
    if [[ -n "${OPENAI_API_KEY:-}" ]]; then
        sed -i "s|^OPENAI_API_KEY=.*|OPENAI_API_KEY=${OPENAI_API_KEY}|" "${DATA_DIR}/.env" 2>/dev/null || echo "OPENAI_API_KEY=${OPENAI_API_KEY}" >> "${DATA_DIR}/.env"
    fi
    if [[ -n "${ANTHROPIC_API_KEY:-}" ]]; then
        sed -i "s|^ANTHROPIC_API_KEY=.*|ANTHROPIC_API_KEY=${ANTHROPIC_API_KEY}|" "${DATA_DIR}/.env" 2>/dev/null || echo "ANTHROPIC_API_KEY=${ANTHROPIC_API_KEY}" >> "${DATA_DIR}/.env"
    fi
    if [[ -n "${OPENROUTER_API_KEY:-}" ]]; then
        sed -i "s|^OPENROUTER_API_KEY=.*|OPENROUTER_API_KEY=${OPENROUTER_API_KEY}|" "${DATA_DIR}/.env" 2>/dev/null || echo "OPENROUTER_API_KEY=${OPENROUTER_API_KEY}" >> "${DATA_DIR}/.env"
    fi
    if [[ -n "${GOOGLE_API_KEY:-}" ]]; then
        sed -i "s|^GOOGLE_API_KEY=.*|GOOGLE_API_KEY=${GOOGLE_API_KEY}|" "${DATA_DIR}/.env" 2>/dev/null || echo "GOOGLE_API_KEY=${GOOGLE_API_KEY}" >> "${DATA_DIR}/.env"
    fi
    if [[ -n "${HF_TOKEN:-}" ]]; then
        sed -i "s|^HF_TOKEN=.*|HF_TOKEN=${HF_TOKEN}|" "${DATA_DIR}/.env" 2>/dev/null || echo "HF_TOKEN=${HF_TOKEN}" >> "${DATA_DIR}/.env"
    fi
    if [[ -n "${CUSTOM_BASE_URL:-}" ]]; then
        sed -i "s|^CUSTOM_BASE_URL=.*|CUSTOM_BASE_URL=${CUSTOM_BASE_URL}|" "${DATA_DIR}/.env" 2>/dev/null || echo "CUSTOM_BASE_URL=${CUSTOM_BASE_URL}" >> "${DATA_DIR}/.env"
    fi
    if [[ -n "${CUSTOM_API_KEY:-}" ]]; then
        sed -i "s|^CUSTOM_API_KEY=.*|CUSTOM_API_KEY=${CUSTOM_API_KEY}|" "${DATA_DIR}/.env" 2>/dev/null || echo "CUSTOM_API_KEY=${CUSTOM_API_KEY}" >> "${DATA_DIR}/.env"
    fi
    if [[ -n "${OLLAMA_HOST:-}" ]]; then
        sed -i "s|^OLLAMA_HOST=.*|OLLAMA_HOST=${OLLAMA_HOST}|" "${DATA_DIR}/.env" 2>/dev/null || echo "OLLAMA_HOST=${OLLAMA_HOST}" >> "${DATA_DIR}/.env"
    fi
} 2>/dev/null || true

# =============================================================================
# Build Docker image if missing
# =============================================================================
info "Building Docker image..."
cd "${WRAPPER_DIR}"
${ENGINE} compose build

# Cleanup old container
${ENGINE} rm -f $($ENGINE ps -aq --filter "name=$CONTAINER_NAME" --filter "status=running") 2>/dev/null || true

# =============================================================================
# Launch
# =============================================================================
info "Starting Hermes for project: ${PROJECT_NAME}"
info "Container: ${CONTAINER_NAME}"
info "Data: ${DATA_DIR}"
info "Workspace: ${PROJECT_DIR}"
info "Provider: ${PROVIDER}"
info "Model: ${MODEL}"

exec $ENGINE compose run --rm hermes
