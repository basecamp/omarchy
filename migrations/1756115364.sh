echo "Replace buggy native Zoom client with webapp"

if omarchy-pkg-present zoom; then
  omarchy-pkg-drop zoom
  omarchy-webapp-install "Zoom" https://app.zoom.us/wc/home https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/zoom.png
fi
