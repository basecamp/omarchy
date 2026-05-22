echo "Add Omarchy URL Handler"

omarchy-refresh-applications

DESKTOP_ID="omarchy-handle-url.desktop"
xdg-mime default "$DESKTOP_ID" x-scheme-handler/http
xdg-mime default "$DESKTOP_ID" x-scheme-handler/https
