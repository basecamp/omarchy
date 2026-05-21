echo "Install MPRIS support for mpv"

if omarchy-pkg-missing mpv-mpris; then
  omarchy-pkg-add mpv-mpris
fi
