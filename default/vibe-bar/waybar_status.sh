#!/bin/bash
# Vibe Bar — Waybar status module script
# Returns JSON for Waybar custom module: {"text":"...","tooltip":"...","class":"..."}

VIBE_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/vibe-agents"
CACHE_FILE="$VIBE_RUNTIME_DIR/waybar.json"

if [[ -f "$CACHE_FILE" ]]; then
  cat "$CACHE_FILE"
else
  echo '{"text": "", "class": "agents-offline"}'
fi
