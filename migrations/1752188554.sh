echo "Update chromium.desktop to ensure we are always using wayland"
if [[ ! -f ~/.local/share/applications/chromium.desktop ]]; then
  cp ~/.local/share/omarchy/applications/chromium.desktop ~/.local/share/applications/
  xdg-settings set default-web-browser chromium.desktop
  xdg-mime default chromium.desktop x-scheme-handler/http
  xdg-mime default chromium.desktop x-scheme-handler/https
fi
