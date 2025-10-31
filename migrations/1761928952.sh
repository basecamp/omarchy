echo "Change Disk Usage to use gdu"

if [[ -f "$APP_DIR/Disk Usage.desktop" ]]; then
  rm "$APP_DIR/Disk Usage.desktop" 
  omarchy-tui-install "Disk Usage" "bash -c 'gdu /'" float "$ICON_DIR/Disk Usage.png"
fi

