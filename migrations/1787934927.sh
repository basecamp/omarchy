echo "Install UWSM drop-in to resolve PCI by-path AQ_DRM_DEVICES"

src="$OMARCHY_PATH/config/uwsm/env-hyprland.d/zz-omarchy-aq-drm"
dst="$HOME/.config/uwsm/env-hyprland.d/zz-omarchy-aq-drm"
old="$HOME/.config/uwsm/env-hyprland.d/99-omarchy-aq-drm"

if [[ -f $src ]] && ! [[ -e $dst || -L $dst ]]; then
  mkdir -p "$(dirname "$dst")"
  cp "$src" "$dst"
fi

# 99- sorts before letter-named user drop-ins under POSIX ls.
# Remove only the exact previously shipped drop-in, not a user file that
# happens to contain the helper source line.
if [[ -f $old ]] && ! [[ -L $old ]] && cmp -s "$old" <(printf '%s\n' \
  '# Rewrite PCI by-path AQ_DRM_DEVICES after user env-hyprland.' \
  "# Aquamarine splits on ':' (hyprwm/aquamarine#167)." \
  '[ -r "${OMARCHY_PATH%/}/default/uwsm/sanitize-aq-drm-devices" ] && . "${OMARCHY_PATH%/}/default/uwsm/sanitize-aq-drm-devices"'); then
  rm -f "$old"
fi
