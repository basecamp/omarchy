# Chromium asks xdg-desktop-portal for org.freedesktop.impl.portal.Secret to get
# the key it encrypts saved passwords and cookies with. The only backend that
# implements Secret is gnome-keyring.portal, and it ships gated `UseIn=gnome`,
# so in a Hyprland session nothing answers: the browser records
# os_crypt.portal.prev_init_success = false and greets the user with "Something
# went wrong when opening your profile. Some features may be unavailable."
#
# Migration 1784508556 already noted that "on Hyprland the xdg-desktop-portal
# Secret backend has no provider and fails" and pinned --password-store so the
# backend at least stops changing underneath people. This gives it the provider,
# which is the other half: gnome-keyring is already a base package and is
# running as the secrets service, it was simply never wired to the portal.
#
# A file at /etc replaces the desktop-specific hyprland-portals.conf rather than
# merging with it, so the Hyprland defaults are restated here.
if [[ ! -f /etc/xdg-desktop-portal/portals.conf ]]; then
  install -d -m 755 /etc/xdg-desktop-portal
  cat >/etc/xdg-desktop-portal/portals.conf <<'PORTALS'
# Omarchy: hand the Secret interface to gnome-keyring. Without it Chromium's
# password store cannot initialise and the browser reports a broken profile.
[preferred]
default=hyprland;gtk
org.freedesktop.impl.portal.Secret=gnome-keyring
PORTALS
  chmod 644 /etc/xdg-desktop-portal/portals.conf
fi
