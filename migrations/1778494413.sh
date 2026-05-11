echo "Replace swaybg with Skwd-wall for wallpaper selection"

omarchy-pkg-add skwd-wall
omarchy-pkg-drop swaybg

if [[ ! -f ~/.config/skwd-wall/config.json ]]; then
  mkdir -p ~/.config/skwd-wall
  cp "$OMARCHY_PATH/config/skwd-wall/config.json" ~/.config/skwd-wall/config.json
fi

omarchy-theme-refresh

systemctl --user daemon-reload
systemctl --user enable --now skwd-daemon.service 2>/dev/null || true

skwd wall apply "{\"type\":\"static\",\"path\":\"$HOME/.config/omarchy/current/background\"}" >/dev/null 2>&1 || true
