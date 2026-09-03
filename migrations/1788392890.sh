echo "Persist apple-gmux panel brightness across reboots"

# systemd-backlight never attaches to gmux_backlight (PNP path_id failure).
# See install/hardware/apple/gmux-backlight.sh. Idempotent: install -Dm644
# rewrites the same static rule, and a second user finds it already in place.
if ! omarchy-hw-apple-gmux; then
  exit 0
fi

# shellcheck source=../install/hardware/apple/gmux-backlight.sh
source "$OMARCHY_PATH/install/hardware/apple/gmux-backlight.sh"

# Real dest lives under /etc. Tests override OMARCHY_GMUX_UDEV_DEST to a
# writable tmp tree and skip the privilege hop.
if (( $(id -u) != 0 )) && [[ $(gmux_udev_dest) == /etc/* ]]; then
  exec sudo --preserve-env=OMARCHY_PATH,OMARCHY_GMUX_UDEV_DEST,OMARCHY_GMUX_UDEV_SRC,OMARCHY_GMUX_BACKLIGHT \
    /bin/bash -euo pipefail "$BASH_SOURCE"
fi

gmux_install_rule
gmux_activate
