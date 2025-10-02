echo "Install Midnight Commander default TUI"

omarchy-pkg-add mc

ICON_DIR="$HOME/.local/share/applications/icons"
SOURCE_ICON="$HOME/.local/share/omarchy/applications/icons/Midnight Commander.png"

if [ -f "$SOURCE_ICON" ]; then
  mkdir -p "$ICON_DIR"
  cp "$SOURCE_ICON" "$ICON_DIR/"
fi

TARGET_ICON="$ICON_DIR/Midnight Commander.png"

if command -v omarchy-tui-install &>/dev/null && [ -f "$TARGET_ICON" ]; then
  omarchy-tui-install "Midnight Commander" "mc" tile "$TARGET_ICON"
fi
