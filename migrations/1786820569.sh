echo "Keep Radeon in low-power mode on hybrid T2 MacBooks"

repair_marker="${OMARCHY_T2_DGPU_REPAIR_MARKER:-/var/lib/omarchy/migrations/1786820569}"
if [[ -e $repair_marker ]]; then
  exit 0
fi

pci_devices="$(lspci -nn)"
if ! grep -q '106b:180[12]' <<<"$pci_devices" ||
  ! grep -q 'VGA compatible controller.*\[8086:' <<<"$pci_devices" ||
  ! grep -q 'VGA compatible controller.*\[1002:' <<<"$pci_devices"; then
  exit 0
fi

service_source="${OMARCHY_T2_DGPU_SERVICE_SOURCE:-$OMARCHY_PATH/default/systemd/system/omarchy-t2-dgpu-low-power.service}"
service_path="${OMARCHY_T2_DGPU_SERVICE_PATH:-/etc/systemd/system/omarchy-t2-dgpu-low-power.service}"

sudo install -Dm644 "$service_source" "$service_path"
sudo systemctl enable omarchy-t2-dgpu-low-power.service
sudo install -Dm644 /dev/null "$repair_marker"
