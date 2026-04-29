echo "Move Obsidian flags from Hyprland binding to Obsidian user flags"

OBSIDIAN_FLAGS_FILE="$HOME/.config/obsidian/user-flags.conf"

mkdir -p "$(dirname "$OBSIDIAN_FLAGS_FILE")"

if [[ ! -f $OBSIDIAN_FLAGS_FILE ]]; then
  cat >"$OBSIDIAN_FLAGS_FILE" <<'EOF'
# Obsidian reads this file through the Arch package wrapper.
--ozone-platform=wayland
--enable-wayland-ime

# If Obsidian crashes because of GPU acceleration, uncomment:
# --disable-gpu
EOF
fi

if [[ -f ~/.config/hypr/bindings.conf ]]; then
  sed -i '/Obsidian, exec/ {
    s/ -disable-gpu//g
    s/ --disable-gpu//g
    s/ --enable-wayland-ime//g
    s/ --ozone-platform=wayland//g
    s/"uwsm app -- obsidian/"uwsm-app -- obsidian/g
  }' ~/.config/hypr/bindings.conf
fi
