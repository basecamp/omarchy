# Detect first-generation Touch Bar MacBook Pros (T1) and install the
# wiring the bar needs. Firmware is machine-specific and is not shipped;
# copy it from a USB that ran copy-t1-firmware.command on macOS.

if omarchy-hw-apple-t1; then
  echo "Detected MacBook with T1 Touch Bar"

  omarchy-pkg-add linux-headers

  # shellcheck source=t1-touchbar.sh
  source "$OMARCHY_INSTALL/hardware/apple/t1-touchbar.sh"

  t1_install_wiring

  if src=$(t1_find_firmware); then
    if esp=$(t1_esp_mount) && t1_copy_firmware "$src" "$esp"; then
      echo "Installed T1 Touch Bar firmware on the EFI partition"
    else
      echo "Found T1 firmware on USB but could not copy it to the EFI partition"
    fi
  else
    echo "No T1 firmware on a mounted USB. After install, plug in the stick from"
    echo "macOS and run:  omarchy setup apple touchbar"
  fi
fi
