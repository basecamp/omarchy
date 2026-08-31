echo "Install UWSM drop-in to resolve PCI by-path AQ_DRM_DEVICES"

src="$OMARCHY_PATH/config/uwsm/env-hyprland.d/zz-omarchy-aq-drm"
dst="$HOME/.config/uwsm/env-hyprland.d/zz-omarchy-aq-drm"
old="$HOME/.config/uwsm/env-hyprland.d/99-omarchy-aq-drm"

if [[ -f $src ]] && ! [[ -e $dst || -L $dst ]]; then
  mkdir -p "$(dirname "$dst")"
  cp "$src" "$dst"
fi

# 99- sorts before letter-named user drop-ins under POSIX ls.
if [[ -f $old ]] && ! [[ -L $old ]] && grep -qxF '[ -r "${OMARCHY_PATH%/}/default/uwsm/sanitize-aq-drm-devices" ] && . "${OMARCHY_PATH%/}/default/uwsm/sanitize-aq-drm-devices"' "$old"; then
  rm -f "$old"
fi
