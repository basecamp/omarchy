echo "Pin Helium's password store to gnome-libsecret (prevents cookie/login loss on Hyprland)"

# Migration 1784508556 pinned the os_crypt backend for the Chromium-based browsers Omarchy knew
# about then, but Helium was not among them, so a Helium install still auto-detects its backend:
# the xdg-desktop-portal Secret backend has no provider on Hyprland and fails, and the browser can
# fall back to the 'basic' (v10) store. That makes every cookie and saved password sealed with the
# gnome-libsecret (v11) key undecryptable, so the browser drops them and the user is logged out of
# everything. omarchy-launch-webapp already treats helium as a supported Chromium-based browser.
#
# Helium's launcher reads ~/.config/helium-browser-flags.conf, named for the helium-browser command
# rather than the profile directory, and 1784508556 only amended flags files that already existed.
# Fresh installs receive the default from config/, while this migration seeds every existing user
# so installing Helium after the migration ran cannot leave the browser unpinned.

helium_flags_file="$HOME/.config/helium-browser-flags.conf"

if [[ ! -f $helium_flags_file ]] || ! grep -Eq '^[[:space:]]*--password-store=' "$helium_flags_file"; then
  mkdir -p "${helium_flags_file%/*}"

  if [[ -f $helium_flags_file && -n $(tail -c1 "$helium_flags_file") ]]; then
    echo >>"$helium_flags_file"
  fi

  echo '--password-store=gnome-libsecret' >>"$helium_flags_file"
fi
