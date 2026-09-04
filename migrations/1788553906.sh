echo "Install Flatpak and configure Flathub so Flatpak apps work out of the box"

OMARCHY_PATH="${OMARCHY_PATH:-/usr/share/omarchy}"
flatpak_config_script="$OMARCHY_PATH/install/config/flatpak.sh"

as_root() {
  if (( EUID == 0 )); then
    "$@"
  else
    sudo "$@"
  fi
}

# Everything this migration does is machine-wide, and the marker that records it
# is per-user. Ask the machine what it already has so the second account on it
# finishes here instead of prompting for a password to redo settled work.
if omarchy-cmd-present flatpak &&
  flatpak remotes --system --columns=name | grep -qx flathub &&
  flatpak override --system --show | grep -q "/usr/share/fonts"; then
  exit 0
fi

# Missing privileges is the one condition worth staying pending for: the fix is
# to run omarchy-migrate again from a terminal that can ask for a password.
if ! omarchy-pkg-add flatpak; then
  echo "Administrator privileges are required to install Flatpak. Run omarchy-migrate again from a terminal." >&2
  exit 1
fi

# The setup leaf is the single description of a configured Flatpak, and new
# installs get it from the ISO. Run the same file rather than keeping a second
# copy of the remote URL and the overrides correct here.
if [[ ! -f $flatpak_config_script ]]; then
  echo "$flatpak_config_script was not found, so Flathub was not configured." >&2
  exit 1
fi

if ! as_root env OMARCHY_PATH="$OMARCHY_PATH" bash -euo pipefail "$flatpak_config_script"; then
  echo "Administrator privileges are required to configure Flathub. Run omarchy-migrate again from a terminal." >&2
  exit 1
fi

# The session reads XDG_DATA_DIRS once, at login, so apps installed before the
# next one are on disk but not yet in the launcher.
echo "Flatpak apps appear in the launcher after the next login."
