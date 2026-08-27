echo "Keep GNOME text scaling from clipping 1Password's fixed-size dialogs"

if omarchy-cmd-present 1password; then
  mkdir -p "$HOME/.local/share/applications"
  install -m 644 "$OMARCHY_PATH/default/applications/1password.desktop" \
    "$HOME/.local/share/applications/1password.desktop"
  update-desktop-database "$HOME/.local/share/applications" 2>/dev/null || true

  # Pick up the packaged autostart drop-in without waiting for a relogin.
  # The running 1Password keeps its old environment until it is restarted.
  systemctl --user daemon-reload
fi
