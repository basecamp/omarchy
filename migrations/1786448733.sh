echo "Invite the upgrade to Omarchy Quattro"

# Pick up the mako rule that makes the invitation clickable
omarchy-restart-mako || true

# Tolerate a missing session so a headless update does not fail on the invitation
notify-send -i "$OMARCHY_PATH/icon.png" "Upgrade to Omarchy Quattro" "The major new version is ready!" -u critical || true
