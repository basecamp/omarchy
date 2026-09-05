# MacBookPro13,3's Radeon Pro 460 can hard-lock during VRAM clock transitions.
# Keep every core and PCIe level available while pinning only VRAM to its
# highest DPM level. Hyprland's initial modeset resets the mask, so a lightweight
# monitor reapplies it immediately and keeps guarding later session transitions.
product_file="${OMARCHY_MBP133_DMI_PRODUCT:-/sys/class/dmi/id/product_name}"
pci_devices="${OMARCHY_MBP133_PCI_DEVICES:-/sys/bus/pci/devices}"
product_name=$(cat "$product_file" 2>/dev/null || true)
gpu_found=0

if [[ $product_name == "MacBookPro13,3" ]]; then
  for candidate in "$pci_devices"/*; do
    [[ -f $candidate/vendor && -f $candidate/device ]] || continue
    if [[ $(<"$candidate/vendor") == 0x1002 && \
          $(<"$candidate/device") == 0x67ef && \
          $(<"$candidate/subsystem_vendor") == 0x106b && \
          $(<"$candidate/subsystem_device") == 0x0160 ]]; then
      gpu_found=1
      break
    fi
  done
fi

if (( gpu_found == 1 )); then
  echo "Detected MacBookPro13,3 Radeon Pro 460; pinning the VRAM clock"

  helper_source="$OMARCHY_INSTALL/hardware/apple/mbp133-amdgpu-stability"
  monitor_source="$OMARCHY_INSTALL/hardware/apple/mbp133-amdgpu-stability-monitor"
  helper_target="${OMARCHY_MBP133_HELPER:-/etc/omarchy/hardware/mbp133-amdgpu-stability}"
  monitor_target="${OMARCHY_MBP133_MONITOR:-/etc/omarchy/hardware/mbp133-amdgpu-stability-monitor}"
  unit_file="${OMARCHY_MBP133_UNIT:-/etc/systemd/system/omarchy-mbp133-amdgpu-stability.service}"
  timer_file="${OMARCHY_MBP133_TIMER:-/etc/systemd/system/omarchy-mbp133-amdgpu-stability.timer}"

  sudo install -D -m 0755 "$helper_source" "$helper_target"
  sudo install -D -m 0755 "$monitor_source" "$monitor_target"
  {
    echo '[Unit]'
    echo 'Description=MacBookPro13,3 Radeon VRAM clock stability workaround'
    echo 'After=systemd-modules-load.service'
    echo 'Before=display-manager.service'
    echo
    echo '[Service]'
    echo 'Type=simple'
    echo "ExecStartPre=$helper_target"
    echo "ExecStart=$monitor_target"
    echo 'Restart=on-failure'
    echo 'RestartSec=1s'
    echo
    echo '[Install]'
    echo 'WantedBy=multi-user.target'
  } | sudo tee "$unit_file" >/dev/null

  sudo systemctl disable --now omarchy-mbp133-amdgpu-stability.timer 2>/dev/null || true
  sudo rm -f "$timer_file"
  sudo systemctl daemon-reload
  sudo systemctl enable omarchy-mbp133-amdgpu-stability.service
fi
