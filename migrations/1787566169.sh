echo "Keep Ghostty terminal launches in the active working directory"

ghostty_config="$HOME/.config/ghostty/config"
ghostty_desktop="$HOME/.local/share/applications/com.mitchellh.ghostty.desktop"

[[ -f $ghostty_config ]] || exit 0

if ! grep -Eq '^[[:space:]]*gtk-single-instance[[:space:]]*=' "$ghostty_config"; then
  printf '\ngtk-single-instance = false\n' >>"$ghostty_config"
fi

if [[ ! -e $ghostty_desktop ]]; then
  mkdir -p "$(dirname "$ghostty_desktop")"
  cp "$OMARCHY_PATH/default/ghostty/com.mitchellh.ghostty.desktop" "$ghostty_desktop"
fi

rm -f "${XDG_CACHE_HOME:-$HOME/.cache}/xdg-terminal-exec"
