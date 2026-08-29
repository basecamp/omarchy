echo "Install UWSM drop-in to resolve PCI by-path AQ_DRM_DEVICES"

src="$OMARCHY_PATH/config/uwsm/env-hyprland.d/99-omarchy-aq-drm"
dst="$HOME/.config/uwsm/env-hyprland.d/99-omarchy-aq-drm"

if [[ -f $src ]] && ! [[ -e $dst || -L $dst ]]; then
  mkdir -p "$(dirname "$dst")"
  cp "$src" "$dst"
fi
