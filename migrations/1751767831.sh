if [ -n "$(lspci | grep -i 'nvidia')" ]; then
  echo "Add GBM_BACKEND env variable for NVIDIA systems"

  HYPRLAND_CONF="$HOME/.config/hypr/hyprland.conf"
  if [ -f "$HYPRLAND_CONF" ]; then
    sed -i -E '/\# NVIDIA environment variables/a env = GBM_BACKEND,nvidia-drm' $HYPRLAND_CONF
  fi
fi
