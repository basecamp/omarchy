echo "Migrate to Omarchy 4.0 package layout"

# Omarchy 4.0 collapses the old git/online-installer layout into the packaged
# runtime layout. Packages own most static system files; these commands refresh
# the machine-specific and user-specific pieces in place.
channel=$(omarchy-version-channel 2>/dev/null | awk '{print $1}')
case "$channel" in
  stable|rc|edge) ;;
  *) channel=stable ;;
esac

# Fold post-4.0 pre-release migration work into the single 4.0 migration.
rm -f "$HOME/.local/bin/playwright-cli"
omarchy-pkg-drop claude-code github-cli

sudo env \
  OMARCHY_PATH="${OMARCHY_PATH:-/usr/share/omarchy}" \
  OMARCHY_INSTALL="${OMARCHY_INSTALL:-${OMARCHY_PATH:-/usr/share/omarchy}/install}" \
  OMARCHY_INSTALL_USER="$USER" \
  OMARCHY_MIRROR="${OMARCHY_MIRROR:-$channel}" \
  /usr/bin/omarchy-setup-system --install-user "$USER" --upgrade

OMARCHY_SETUP_CONTEXT=runtime omarchy-setup-user --force
omarchy-refresh-applications
