# Shared Apple T1 Touch Bar detection for fresh installs and migrations.

t1_touchbar_dmi_product() {
  cat "${OMARCHY_T1_DMI_PRODUCT:-/sys/class/dmi/id/product_name}" 2>/dev/null || true
}

t1_touchbar_usb_devices() {
  printf '%s\n' "${OMARCHY_T1_USB_DEVICES:-/sys/bus/usb/devices}"
}

t1_touchbar_needed() {
  local device usb_devices
  [[ $(t1_touchbar_dmi_product) == "MacBookPro13,3" ]] || return 1

  usb_devices=$(t1_touchbar_usb_devices)
  for device in "$usb_devices"/*; do
    [[ -f $device/idVendor && -f $device/idProduct ]] || continue
    if [[ $(<"$device/idVendor") == 05ac && $(<"$device/idProduct") == 8600 ]]; then
      return 0
    fi
  done
  return 1
}
