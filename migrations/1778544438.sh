echo "Prime Quickshell Omarchy menu styling"

AUTOSTART_FILE="$HOME/.config/hypr/autostart.lua"
if [[ -f $AUTOSTART_FILE ]] && grep -q 'omarchy-menu --daemon' "$AUTOSTART_FILE"; then
  sed -i '/omarchy-menu --daemon/d' "$AUTOSTART_FILE"
fi

TOGGLES_DIR="$HOME/.local/state/omarchy/toggles"
QUICKSHELL_MENU_STYLE="$TOGGLES_DIR/quickshell-menu.json"
mkdir -p "$TOGGLES_DIR"

if [[ ! -f $QUICKSHELL_MENU_STYLE ]]; then
  radius=0
  if [[ -f $TOGGLES_DIR/walker.css ]] && grep -q 'border-radius: 6px;' "$TOGGLES_DIR/walker.css"; then
    radius=6
  fi

  printf '{ "radius": %s }\n' "$radius" >"$QUICKSHELL_MENU_STYLE"
fi

THEME_DIR="$HOME/.config/omarchy/current/theme"
COLORS_FILE="$THEME_DIR/colors.toml"
MENU_COLORS_FILE="$THEME_DIR/menu.json"

color_value() {
  local key="$1"
  local value
  value=$(grep -E "^[[:space:]]*$key[[:space:]]*=" "$COLORS_FILE" | head -1)
  value="${value#*=}"
  value="${value//\"/}"
  value="${value//\'/}"
  value="${value//[[:space:]]/}"
  printf '%s' "$value"
}

if [[ -f $COLORS_FILE && ! -f $MENU_COLORS_FILE ]]; then
  accent=$(color_value accent)
  background=$(color_value background)
  foreground=$(color_value foreground)

  cat >"$MENU_COLORS_FILE" <<JSON
{
  "accent": "${accent:-#89b4fa}",
  "background": "${background:-#101315}",
  "foreground": "${foreground:-#cacccc}",
  "border": "${foreground:-#cacccc}"
}
JSON
fi

rm -rf "${XDG_CACHE_HOME:-$HOME/.cache}/omarchy/menu"

if omarchy-cmd-present hyprctl; then
  hyprctl reload >/dev/null 2>&1 || true
fi
