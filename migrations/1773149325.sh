echo "Install NetBird TUI for managing WireGuard mesh VPN"

APP_DIR="$HOME/.local/share/applications"
ICON_DIR="$APP_DIR/icons"

omarchy-pkg-add netbird-tui

mkdir -p "$ICON_DIR"
cp "$OMARCHY_PATH/applications/icons/NetBird.png" "$ICON_DIR/NetBird.png"

omarchy-tui-install "NetBird" "sudo netbird-tui" float "$ICON_DIR/NetBird.png"
