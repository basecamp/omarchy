echo "Enable pause_media in voxtype config"

VOXTYPE_CONF=~/.config/voxtype/config.toml

if [[ -f $VOXTYPE_CONF ]] && ! grep -q 'pause_media' "$VOXTYPE_CONF"; then
  if grep -q '^\[audio\]' "$VOXTYPE_CONF"; then
    sed -i '/^\[audio\]/a\
\
# Pause MPRIS media players during recording\
pause_media = true' "$VOXTYPE_CONF"
  else
    printf '\n[audio]\n# Pause MPRIS media players during recording\npause_media = true\n' >> "$VOXTYPE_CONF"
  fi
fi
