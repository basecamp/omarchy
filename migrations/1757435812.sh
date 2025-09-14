echo "Update Zoom webapp to handle zoommtg:// and zoomus:// protocol links"

# Check if Zoom webapp is installed
if [[ -f ~/.local/share/applications/Zoom.desktop ]]; then
  # Remove old Zoom webapp and reinstall with protocol handler support
  omarchy-webapp-remove "Zoom"
  omarchy-webapp-install "Zoom" https://app.zoom.us/wc/home https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/zoom.png "omarchy-webapp-handler-zoom %u" "x-scheme-handler/zoommtg;x-scheme-handler/zoomus"
fi
