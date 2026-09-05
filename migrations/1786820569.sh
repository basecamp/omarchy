echo "Install T1 Touch Bar wiring and copy firmware from a USB stick if present"

# First-generation Touch Bar MacBook Pros only. Other Apple hardware is
# unchanged. See install/hardware/apple/t1-touchbar.sh for the USB handoff.
if ! omarchy-hw-apple-t1; then
  exit 0
fi

# shellcheck source=../install/hardware/apple/t1-touchbar.sh
source "$OMARCHY_PATH/install/hardware/apple/t1-touchbar.sh"

# Real dests live under /etc and /boot. Tests override OMARCHY_T1_* to a
# writable tmp tree and skip the privilege hop.
if (( $(id -u) != 0 )) && [[ $(t1_udev_rule_dest) == /etc/* ]]; then
  exec sudo --preserve-env=OMARCHY_PATH,OMARCHY_T1_UDEV_DEST,OMARCHY_T1_UDEV_SRC,OMARCHY_T1_MODULES_LOAD,OMARCHY_T1_ESP,OMARCHY_T1_MEDIA_ROOTS,OMARCHY_T1_COLLECTOR,OMARCHY_DMI_PRODUCT_NAME \
    /bin/bash -euo pipefail "$OMARCHY_PATH/migrations/1786820569.sh"
fi

omarchy-pkg-add linux-headers

t1_install_wiring

if src=$(t1_find_firmware); then
  if esp=$(t1_esp_mount); then
    if ! t1_copy_firmware "$src" "$esp"; then
      echo "Found T1 firmware on USB but could not copy it to the EFI partition."
      echo "Wiring is installed; later run: omarchy setup apple touchbar"
    fi
  fi
fi
