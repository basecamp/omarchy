pci_devices="$(lspci -nn)"

if grep -q '106b:180[12]' <<<"$pci_devices" &&
  grep -q 'VGA compatible controller.*\[8086:' <<<"$pci_devices" &&
  grep -q 'VGA compatible controller.*\[1002:' <<<"$pci_devices"; then
  service_source="${OMARCHY_T2_DGPU_SERVICE_SOURCE:-$OMARCHY_PATH/default/systemd/system/omarchy-t2-dgpu-off.service}"
  service_path="${OMARCHY_T2_DGPU_SERVICE_PATH:-/etc/systemd/system/omarchy-t2-dgpu-off.service}"

  install -Dm644 "$service_source" "$service_path"
  systemctl enable omarchy-t2-dgpu-off.service
fi
