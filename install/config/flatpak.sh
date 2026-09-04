# Flatpak ships with no remotes configured, so a fresh install can see every
# app and install none of them. Flathub is where the apps Omarchy points users
# at actually live, and adding it here means the ISO hands over a machine where
# `omarchy flatpak add` already works.
flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo

# A sandboxed app sees the runtime's fonts and icons, not the host's, so
# without these it renders in a fallback font and with a different icon set
# than everything else on the desktop. Read-only, and narrowed to the two
# directories the look actually comes from: this is theming, not an opening of
# the sandbox. Omarchy's own GTK appearance travels over the settings portal,
# which xdg-desktop-portal-gtk already serves, so nothing here needs to
# restate the theme.
flatpak override --system --filesystem=/usr/share/fonts:ro
flatpak override --system --filesystem=/usr/share/icons:ro
