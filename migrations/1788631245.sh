echo "Pin Electron password store to gnome-libsecret (prevents keyring errors on Hyprland)"

# Migration 1784508556 pinned the os_crypt backend for Chromium-based browsers.
# Distro Electron apps (Element and anything else launched through Arch's
# electronN wrapper) still auto-detect: Hyprland is not GNOME/KDE, so the
# xdg-desktop-portal Secret backend has no matching provider and Electron
# reports an unsupported keyring or falls back to basic_text. A profile sealed
# with the wrong backend then cannot be opened.
#
# The wrapper reads ~/.config/electronN-flags.conf if present, otherwise
# ~/.config/electron-flags.conf. Fresh installs receive the default from
# config/; this migration seeds existing users and pins any versioned flags
# files that would otherwise shadow the fallback. An explicit
# --password-store= line is left alone.

pin_electron_flags() {
  local flags_file=$1

  if [[ ! -f $flags_file ]] || ! grep -Eq '^[[:space:]]*--password-store=' "$flags_file"; then
    mkdir -p "${flags_file%/*}"

    if [[ -f $flags_file && -n $(tail -c1 "$flags_file") ]]; then
      echo >>"$flags_file"
    fi

    echo '--password-store=gnome-libsecret' >>"$flags_file"
  fi
}

pin_electron_flags "$HOME/.config/electron-flags.conf"

shopt -s nullglob
for flags_file in "$HOME"/.config/electron[0-9]*-flags.conf; do
  pin_electron_flags "$flags_file"
done
