echo "Give the Secret portal a provider so Chromium can open its password store"

# Chromium asks xdg-desktop-portal for org.freedesktop.impl.portal.Secret. The
# only backend implementing it is gnome-keyring.portal, gated `UseIn=gnome`, so
# on Hyprland nothing answers and the browser reports a broken profile:
# "Something went wrong when opening your profile. Some features may be
# unavailable." Migration 1784508556 pinned --password-store so the backend
# stopped changing; this supplies the provider it was asking for.
#
# Only written when the file is absent: a portals.conf already in place is the
# user's, and replacing the Secret line under them could move where their
# existing secrets are read from.
if [[ ! -f /etc/xdg-desktop-portal/portals.conf ]]; then
  sudo install -d -m 755 /etc/xdg-desktop-portal
  sudo tee /etc/xdg-desktop-portal/portals.conf >/dev/null <<'PORTALS'
# Omarchy: hand the Secret interface to gnome-keyring. Without it Chromium's
# password store cannot initialise and the browser reports a broken profile.
[preferred]
default=hyprland;gtk
org.freedesktop.impl.portal.Secret=gnome-keyring
PORTALS
  sudo chmod 644 /etc/xdg-desktop-portal/portals.conf
  systemctl --user restart xdg-desktop-portal 2>/dev/null || true
fi
