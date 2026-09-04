# Unload BCM4377b Wi-Fi around sleep so T2 Macs actually reach S3.
#
# brcmfmac times out entering PCI D3 (-EIO). The kernel aborts suspend,
# logind retries, and a lid-closed machine stays awake (~10 W).
#
# Only BCM4377b (14e4:4488). BCM4364 (14e4:4464) must keep brcmfmac bound.
# Do not change mem_sleep_default; t2bce + pm_async=off reaches real S3
# once this chip is out of the way. Do not enable --now: that would drop
# Wi-Fi until the next resume.
#
# Keep /etc/modprobe.d/brcmfmac.conf owned by fix-brcmfmac-supplicant.sh.

if omarchy-hw-t2-bcm4377; then
  echo "Detected T2 Mac with BCM4377b. Unloading Wi-Fi around sleep."

  unit="${OMARCHY_T2_BCM4377_UNIT:-/etc/systemd/system/omarchy-t2-bcm4377-sleep.service}"
  src="${OMARCHY_INSTALL:-$OMARCHY_PATH/install}/hardware/apple/omarchy-t2-bcm4377-sleep.service"
  install -Dm644 "$src" "$unit"
  systemctl daemon-reload
  systemctl enable omarchy-t2-bcm4377-sleep.service

  # Replace a hand-installed t2-bcm4377-sleep.service if one is still present.
  legacy_unit="${OMARCHY_T2_BCM4377_LEGACY_UNIT:-/etc/systemd/system/t2-bcm4377-sleep.service}"
  legacy_script="${OMARCHY_T2_BCM4377_LEGACY_SCRIPT:-/usr/local/sbin/t2-bcm4377-sleep.sh}"
  legacy_fan_lib="${OMARCHY_T2_BCM4377_LEGACY_FAN_LIB:-/usr/lib/systemd/system-sleep/t2-fan.sh}"
  legacy_fan_etc="${OMARCHY_T2_BCM4377_LEGACY_FAN_ETC:-/etc/systemd/system-sleep/t2-fan.sh}"
  if [[ -f $legacy_unit ]]; then
    systemctl disable t2-bcm4377-sleep.service 2>/dev/null || true
    rm -f "$legacy_unit" "$legacy_script" "$legacy_fan_lib" "$legacy_fan_etc"
    systemctl daemon-reload
  fi
fi
