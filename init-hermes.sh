#!/usr/bin/env bash
# =============================================================================
# init-hermes — Clone, build, and run Hermes Agent for a project
# =============================================================================
# Drop this script somewhere on PATH:
#   sudo cp init-hermes.sh /usr/local/bin/
#
# Usage:
#   cd ~/my-project
#   init-hermes                          # clones, builds, runs
#
# The wrapper lives in .hermes-compose/ (hidden sibling dir).
# Data persists in ../.hermes/ (sibling to wrapper).
# =============================================================================

set -euo pipefail

# --- Colors ---
ok()   { echo -e "\033[32m✔\033[0m $*"; }
info() { echo -e "\033[34mℹ\033[0m $*"; }
warn() { echo -e "\033[33m⚠\033[0m $*"; }
err()  { echo -e "\033[31m✘\033[0m $*" >&2; exit 1; }

# --- Symlink resolution: find where the script lives, not where it's called from ---
SOURCE="${BASH_SOURCE[0]}"
while [ -h "$SOURCE" ]; do
    DIR="$(cd -P "$(dirname "$SOURCE")" >/dev/null 2>&1 && pwd)"
    SOURCE="$(readlink "$SOURCE")"
    [[ "$SOURCE" != /* ]] && SOURCE="$DIR/$SOURCE"
done
SCRIPT_DIR="$(cd -P "$(dirname "$SOURCE")" >/dev/null 2>&1 && pwd)"

# --- Detect container runtime ---
ENGINE=docker
if command -v podman &>/dev/null; then
    ENGINE=podman
elif command -v docker &>/dev/null; then
    ENGINE=docker
else
    err "No container runtime found (need docker or podman)"
fi

# --- Resolve wrapper directory (.hermes-compose) relative to current project ---
PROJECT_DIR="$(pwd)"
WRAPPER_DIR="${PROJECT_DIR}/.hermes-compose"
DATA_DIR="${PROJECT_DIR}/.hermes"
COMPOSE_FILE="${WRAPPER_DIR}/docker-compose.yml"

# --- Dynamic container name from project dir ---
PROJECT_NAME="${PWD##*/}"
CONTAINER_NAME="hermes-${PROJECT_NAME//-/}"

# --- Clone or pull wrapper ---
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

# --- Ensure data directory exists (sibling to wrapper) ---
if [[ ! -d "${DATA_DIR}" ]]; then
    mkdir -p "${DATA_DIR}"
    ok "Created data directory: ${DATA_DIR}"
fi

# --- Validate or configure API key ---
if [[ -z "${NVIDIA_API_KEY:-}" ]]; then
    warn "NVIDIA_API_KEY is not set."
    if [[ -t 0 ]]; then
        read -p "Would you like to configure your model/API key now? [y/N] " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            info "Launching Hermes model configuration..."
            # We're already in $SCRIPT_DIR which is .hermes-compose/
            # Run hermes model (which will ask for API key interactively)
            # or guide the user to set it
            if command -v hermes &>/dev/null; then
                # If Hermes is installed on host, use it to configure
                hermes model || warn "Model configuration exited with errors"
            else
                # No Hermes on host — create a .env placeholder and let entrypoint handle it
                info "No 'hermes' CLI on host. Creating .env with placeholder."
                info "You'll be prompted for the key on first run."
            fi
            # After configuration, try to read the key from .env
            if [[ -f "${DATA_DIR}/.env" ]] && grep -q "^NVIDIA_API_KEY=" "${DATA_DIR}/.env" 2>/dev/null; then
                NVIDIA_API_KEY=$(grep "^NVIDIA_API_KEY=" "${DATA_DIR}/.env" | cut -d= -f2-)
                info "Found NVIDIA_API_KEY in .env"
            fi
        else
            info "Skipping configuration. Exiting."
            exit 0
        fi
    else
        err "NVIDIA_API_KEY is not set (and stdin is not a TTY).\n  Set it in your environment or .env file.\n  Get a free key at: https://build.nvidia.com/settings/api-keys"
    fi
fi

# --- SSH key setup (optional) ---
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

# --- Check if .env exists, create from example if not ---
if [[ ! -f "${DATA_DIR}/.env" ]]; then
    if [[ -f "${WRAPPER_DIR}/.env.example" ]]; then
        cp "${WRAPPER_DIR}/.env.example" "${DATA_DIR}/.env"
        sed -i "s|NVIDIA_API_KEY=.*|NVIDIA_API_KEY=${NVIDIA_API_KEY}|" "${DATA_DIR}/.env"
        info "Created .env from template"
    fi
fi

# --- Build Docker image if missing ---
info "Building Docker image..."
cd "${WRAPPER_DIR}"
$ENGINE compose build

# --- Cleanup old container ---
$ENGINE rm -f $($ENGINE ps -aq --filter "name=$CONTAINER_NAME" --filter "status=running") 2>/dev/null || true

# --- Launch ---
info "Starting Hermes for project: ${PROJECT_NAME}"
info "Container: ${CONTAINER_NAME}"
info "Data: ${DATA_DIR}"
info "Workspace: ${PROJECT_DIR}"

exec $ENGINE compose run --rm hermes
