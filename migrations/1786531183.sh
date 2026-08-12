echo "Route http(s) links through omarchy-url-open so Spotify links open in the native app"

# Preserve the user's current browser choice in the text/html handler,
# which omarchy-url-open uses as its fallback
current_browser=$(xdg-mime query default x-scheme-handler/http)
if [[ -n $current_browser && $current_browser != omarchy-url-open.desktop ]]; then
  xdg-mime default "$current_browser" text/html
fi

cp "$OMARCHY_PATH/applications/omarchy-url-open.desktop" ~/.local/share/applications/
update-desktop-database ~/.local/share/applications

xdg-mime default omarchy-url-open.desktop x-scheme-handler/http
xdg-mime default omarchy-url-open.desktop x-scheme-handler/https
