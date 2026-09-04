# Install MIPI camera support for Intel IPU7 hardware

# The ov08x40 sensor (OVTI08F4) sits behind IPU6 on Meteor Lake as much as behind IPU7 on
# Panther Lake, so the controller decides; intel-ipu7-camera builds the ipu75xa HAL alone.
acpi_devices="${OMARCHY_ACPI_DEVICES_PATH:-/sys/bus/acpi/devices}"

if pci_devices=$(lspci -nn) &&
  grep -q "OVTI08F4" "$acpi_devices"/*/hid 2>/dev/null &&
  grep -qi '\[8086:b05d\]' <<<"$pci_devices"; then
  omarchy-pkg-add intel-ipu7-camera
fi
