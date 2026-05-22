echo "Add Omarchy URL Handler"

omarchy-refresh-applications

APP_DIR="$HOME/.local/share/applications"
if omarchy-cmd-present update-desktop-database; then
  update-desktop-database "$APP_DIR" &>/dev/null || true
fi

DESKTOP_ID="omarchy-handle-url.desktop"
xdg-mime default "$DESKTOP_ID" x-scheme-handler/http
xdg-mime default "$DESKTOP_ID" x-scheme-handler/https
