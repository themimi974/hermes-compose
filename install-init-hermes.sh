#!/usr/bin/env bash
set -euo pipefail

# ═══════════════════════════════════════════════════════════════════
# install-init-hermes - Install init-hermes to system
# ═══════════════════════════════════════════════════════════════════

ok()   { echo -e "\033[32m✔\033[0m $*"; }
info() { echo -e "\033[34mℹ\033[0m $*"; }
warn() { echo -e "\033[33m⚠\033[0m $*"; }
err()  { echo -e "\033[31m✘\033[0m $*"; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INIT_SCRIPT="$SCRIPT_DIR/init-hermes.sh"

# --- Verify source script exists ---
if [[ ! -f "$INIT_SCRIPT" ]]; then
    err "init-hermes.sh not found at $INIT_SCRIPT"
fi

# --- Detect container runtime ---
if command -v podman &>/dev/null; then
    ENGINE=podman
elif command -v docker &>/dev/null; then
    ENGINE=docker
else
    err "No container runtime found (need docker or podman)"
fi

ok "Detected container runtime: $ENGINE"

# --- Check if running as root or in user's PATH ---
if [[ $EUID -eq 0 ]]; then
    TARGET_DIR="/usr/local/bin"
else
    TARGET_DIR="$HOME/.local/bin"
fi

mkdir -p "$TARGET_DIR"

# --- Check for existing install ---
if [[ -f "$TARGET_DIR/init-hermes" ]]; then
    warn "init-hermes already exists at $TARGET_DIR/init-hermes"
    read -p "Overwrite? [y/N] " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        info "Cancelled."
        exit 0
    fi
fi

# --- Copy script ---
cp "$INIT_SCRIPT" "$TARGET_DIR/init-hermes"
chmod +x "$TARGET_DIR/init-hermes"

ok "Installed to $TARGET_DIR/init-hermes"

# --- Add to PATH if needed ---
if [[ ":$PATH:" != *":$TARGET_DIR:"* ]]; then
    if [[ $EUID -eq 0 ]]; then
        ok "Added to PATH (system-wide)"
    else
        info "Add this to your shell config (~/.bashrc, ~/.zshrc):"
        echo ""
        echo "    export PATH=\"\$PATH:$TARGET_DIR\""
        echo ""
    fi
fi

ok "Installation complete!"
info "Run: init-hermes"
