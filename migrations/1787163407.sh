echo "Install and activate zram swap"

if omarchy-pkg-missing zram-generator; then
  omarchy-pkg-add zram-generator
fi

# Migration markers are per-user, while this repair is machine-wide. A later
# user must leave an already repaired machine alone.
if ! systemctl is-active --quiet dev-zram0.swap; then
  if ! sudo systemctl daemon-reload ||
    ! sudo systemctl start dev-zram0.swap ||
    ! systemctl is-active --quiet dev-zram0.swap; then
    # Live activation failed. Fall back to the update pipeline's reboot prompt.
    omarchy-state set reboot-required
  fi
fi
