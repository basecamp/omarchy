#!/usr/bin/env bash
set -euo pipefail

echo "Remove fingerprint icon from hyprlock.conf if fingerprint setup not run"

# Check if fprintd is installed and configured
if ! fprintd-verify &>/dev/null; then
    # Remove fingerprint icon and auth section from hyprlock.conf if they exist
    if [ -f ~/.config/hypr/hyprlock.conf ]; then
        sed -i -E 's|^\s*placeholder_text\s*=.*Enter Password.*$|    placeholder_text =   Enter Password|' ~/.config/hypr/hyprlock.conf
        sed -i '/^auth {$/,/^}$/d' ~/.config/hypr/hyprlock.conf
    fi
fi
