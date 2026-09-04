echo "Keep Ghostty terminal launches in the active working directory"

ghostty_desktop="$HOME/.local/share/applications/com.mitchellh.ghostty.desktop"
ghostty_configs=()

if [[ -f $HOME/.config/ghostty/config ]]; then
  ghostty_configs+=("$HOME/.config/ghostty/config")
fi
if [[ -f $HOME/.config/ghostty/config.ghostty ]]; then
  ghostty_configs+=("$HOME/.config/ghostty/config.ghostty")
fi

(( ${#ghostty_configs[@]} > 0 )) || exit 0

if ! grep -Eq '^[[:space:]]*gtk-single-instance[[:space:]]*=' "${ghostty_configs[@]}"; then
  printf '\ngtk-single-instance = false\n' >>"${ghostty_configs[-1]}"
fi

if [[ ! -e $ghostty_desktop && ! -L $ghostty_desktop ]]; then
  mkdir -p "$(dirname "$ghostty_desktop")"
  cp "$OMARCHY_PATH/default/ghostty/com.mitchellh.ghostty.desktop" "$ghostty_desktop"
fi

rm -f "${XDG_CACHE_HOME:-$HOME/.cache}/xdg-terminal-exec"
