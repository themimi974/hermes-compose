#!/usr/bin/env bash
set -euo pipefail

# ═══════════════════════════════════════════════════════════════════
# uninstall-init-hermes - Remove init-hermes from system
# ═══════════════════════════════════════════════════════════════════

ok()   { echo -e "\033[32m✔\033[0m $*"; }
info() { echo -e "\033[34mℹ\033[0m $*"; }
warn() { echo -e "\033[33m⚠\033[0m $*"; }
err()  { echo -e "\033[31m✘\033[0m $*"; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --- Detect where it was installed ---
if [[ -f "/usr/local/bin/init-hermes" ]]; then
    INSTALLED_PATH="/usr/local/bin/init-hermes"
    TARGET_DIR="/usr/local/bin"
elif [[ -f "$HOME/.local/bin/init-hermes" ]]; then
    INSTALLED_PATH="$HOME/.local/bin/init-hermes"
    TARGET_DIR="$HOME/.local/bin"
else
    err "init-hermes not found in PATH. Is it installed?"
fi

# --- Confirm uninstall ---
echo "Found installed at: $INSTALLED_PATH"
read -p "Uninstall? [y/N] " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    info "Cancelled."
    exit 0
fi

# --- Remove installed script ---
rm -f "$INSTALLED_PATH"
ok "Removed $INSTALLED_PATH"

# --- Remove .hermes-compose from current directory if exists ---
if [[ -d "$(cd "$SCRIPT_DIR" >/dev/null 2>&1 && cd .. && pwd)/.hermes-compose" ]]; then
    read -p "Remove .hermes-compose/ from parent dir? [y/N] " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        rm -rf "$(cd "$SCRIPT_DIR" >/dev/null 2>&1 && cd .. && pwd)/.hermes-compose"
        ok "Removed .hermes-compose/ from parent dir"
    fi
fi

# --- Check if ~/.local/bin is empty ---
if [[ "$TARGET_DIR" == "$HOME/.local/bin" ]] && [[ -d "$HOME/.local/bin" ]]; then
    if [[ -z "$(ls -A "$HOME/.local/bin" 2>/dev/null)" ]]; then
        warn "$HOME/.local/bin is now empty. You can remove it if you want."
    fi
fi

ok "Uninstallation complete!"
