echo "Add nightlight temperature environment variables to uwsm/default"

UWSM_CONFIG=~/.config/uwsm/default

if [[ -f $UWSM_CONFIG ]]; then
  if ! grep -q 'export OMARCHY_NIGHTLIGHT_ON_TEMPERATURE=' $UWSM_CONFIG; then
    cat <<'EOF' >> $UWSM_CONFIG

# Use a custom temperature for nightlight mode
# export OMARCHY_NIGHTLIGHT_ON_TEMPERATURE=4000
EOF
  fi

  if ! grep -q 'export OMARCHY_NIGHTLIGHT_OFF_TEMPERATURE=' $UWSM_CONFIG; then
    cat <<'EOF' >> $UWSM_CONFIG

# Use a custom temperature for daylight mode
# export OMARCHY_NIGHTLIGHT_OFF_TEMPERATURE=6000
EOF
  fi
else
  omarchy-refresh-config uwsm/default
fi
