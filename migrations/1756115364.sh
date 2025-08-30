echo "Replace buggy native Zoom client with webapp"

if pkg-present zoom; then
  pkg-remove zoom
  omarchy-webapp-install "Zoom" https://app.zoom.us/wc/home https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/zoom.png
fi
