echo "Move Obsidian flags from Hyprland binding to Obsidian user flags"

OBSIDIAN_FLAGS_FILE="$HOME/.config/obsidian/user-flags.conf"
OBSIDIAN_DEFAULT_FLAGS_FILE="$OMARCHY_PATH/config/obsidian/user-flags.conf"

mkdir -p "$(dirname "$OBSIDIAN_FLAGS_FILE")"

if [[ ! -f $OBSIDIAN_FLAGS_FILE ]]; then
  cp "$OBSIDIAN_DEFAULT_FLAGS_FILE" "$OBSIDIAN_FLAGS_FILE"
else
  missing_flags=$(grep -vE '^(#|$)' "$OBSIDIAN_DEFAULT_FLAGS_FILE" | grep -vxFf "$OBSIDIAN_FLAGS_FILE" || true)

  if [[ -n $missing_flags ]]; then
    {
      echo
      echo "# Added by Omarchy migration 1776434586: Obsidian launch flags moved from Hyprland binding."
      printf "%s\n" "$missing_flags"
    } >>"$OBSIDIAN_FLAGS_FILE"
  fi
fi

if [[ -f ~/.config/hypr/bindings.conf ]]; then
  sed -i '/Obsidian, exec/ {
    s/ -disable-gpu//g
    s/ --disable-gpu//g
    s/ --enable-wayland-ime//g
    s/"uwsm app -- obsidian/"uwsm-app -- obsidian/g
  }' ~/.config/hypr/bindings.conf
fi
