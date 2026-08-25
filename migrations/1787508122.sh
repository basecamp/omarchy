echo "Route file chooser portal requests to Nautilus"

source "$OMARCHY_PATH/install/user/xdg-desktop-portal.sh"

# Never fail the migration on an unreachable user bus. omarchy-migrate runs each
# migration with strict error handling and only marks it complete afterwards,
# so a nonzero exit here would also skip every later pending migration. When
# there is no user bus, there is no running portal to restart either.
systemctl --user reload dbus-broker.service >/dev/null 2>&1 || true
systemctl --user try-restart xdg-desktop-portal.service >/dev/null 2>&1 || true
