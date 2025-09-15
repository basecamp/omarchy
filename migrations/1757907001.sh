echo "Enable Waybar mpris module (built-in)"

CFG="$HOME/.config/waybar/config.jsonc"

if [[ -f "$CFG" ]] && grep -q '"mpris"' "$CFG"; then
  echo "mpris already present in Waybar config; skipping."
  exit 0
fi

if command -v gum >/dev/null 2>&1; then
  gum confirm "Replace current Waybar config (backup will be made) to enable the mpris module?" && omarchy-refresh-waybar || true
else
  echo "Replacing Waybar config to enable mpris..."
  omarchy-refresh-waybar
fi
