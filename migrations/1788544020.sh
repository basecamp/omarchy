echo "Unload BCM4377 Wi-Fi around sleep on T2 Macs"

# Existing Quattro installs already have mem_sleep_default=deep and t2bce.
# BCM4377b still aborts that S3 attempt. Install the sleep oneshot only when
# the chip is present; leave BCM4364 and non-T2 machines alone. Do not move
# t2bce machines onto s2idle.

if ! omarchy-hw-t2-bcm4377; then
  exit 0
fi

unit="${OMARCHY_T2_BCM4377_UNIT:-/etc/systemd/system/omarchy-t2-bcm4377-sleep.service}"
src="${OMARCHY_PATH}/install/hardware/apple/omarchy-t2-bcm4377-sleep.service"
legacy_unit="${OMARCHY_T2_BCM4377_LEGACY_UNIT:-/etc/systemd/system/t2-bcm4377-sleep.service}"
legacy_script="${OMARCHY_T2_BCM4377_LEGACY_SCRIPT:-/usr/local/sbin/t2-bcm4377-sleep.sh}"
legacy_fan_lib="${OMARCHY_T2_BCM4377_LEGACY_FAN_LIB:-/usr/lib/systemd/system-sleep/t2-fan.sh}"
legacy_fan_etc="${OMARCHY_T2_BCM4377_LEGACY_FAN_ETC:-/etc/systemd/system-sleep/t2-fan.sh}"

if [[ ! -f $unit ]]; then
  sudo install -Dm644 "$src" "$unit"
  sudo systemctl daemon-reload
  sudo systemctl enable omarchy-t2-bcm4377-sleep.service
fi

if [[ -f $legacy_unit ]]; then
  sudo systemctl disable t2-bcm4377-sleep.service 2>/dev/null || true
  sudo rm -f "$legacy_unit" "$legacy_script" "$legacy_fan_lib" "$legacy_fan_etc"
  sudo systemctl daemon-reload
fi
