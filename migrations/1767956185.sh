MPV_CONFIG_PATH="$HOME/.config/mpv/mpv.conf"

if [[ ! -f "$MPV_CONFIG_PATH" ]]; then
  mkdir -p "$(dirname "$MPV_CONFIG_PATH")"
  cp "$HOME/.local/share/omarchy/config/mpv/mpv.conf" "$MPV_CONFIG_PATH"

  exit 0
fi

# If line does not match (could fail if overwritten by user below it)
if ! grep -Fxq "target-colorspace-hint=no" "$MPV_CONFIG_PATH"; then

  # Delete all semi-matching lines
  sed -i "/^#\? *target-colorspace-hint/d" "$MPV_CONFIG_PATH"

  # File mightn't end on a newline
  [[ -n $(tail -c1 "$MPV_CONFIG_PATH") ]] && echo "" >> "$MPV_CONFIG_PATH"

  {
      echo "# Temporary fullscreen support to prevent washed-out colors"
      echo "target-colorspace-hint=no"
  } >> "$MPV_CONFIG_PATH"

  echo "Added temporary Wayland compatibility for mpv"
fi
