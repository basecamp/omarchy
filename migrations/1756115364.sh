echo "Replace buggy native Zoom client with webapp"

if pacman -Q zoom >/dev/null; then
  sudo pacman -Rns --noconfirm zoom
  omarchy-webapp-install "Zoom" https://app.zoom.us/wc/home https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/zoom.png
fi
