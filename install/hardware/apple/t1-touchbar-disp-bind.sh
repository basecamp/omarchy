# Shared helpers for the T1 Touch Bar display-bind fix (install leaf + migration).
#
# apple-ib-tb spawns a virtual Touch Bar sub-device (1D6B:0301) once the
# iBridge's 05AC:8600 HID interfaces are on apple-ibridge-hid. That
# sub-device carries the "display on" field, but it does not reliably win
# its own auto-bind race, so the bar can show icons and still stay dark.
# See bin/omarchy-hw-apple-t1-touchbar-disp-bind for the rebind itself and
# https://github.com/csk-grit42/OmarchyOnMacBookPro14.2-2017---A1706-/blob/main/HOWTO.md
# (Part 2) for how this was diagnosed on a MacBookPro14,2.
#
# This only rebinds the sub-device; it needs a T1 Touch Bar driver already
# on the system (apple-ib-tb / apple-ibridge — see #7064) to have anything
# to act on.

t1_touchbar_disp_rule_dest() {
  printf '%s\n' "${OMARCHY_T1_DISP_RULE_DEST:-/etc/udev/rules.d/91-apple-t1-touchbar-disp.rules}"
}

t1_touchbar_disp_needed() {
  local product_name
  product_name=$(cat "${OMARCHY_DMI_PRODUCT_NAME:-/sys/class/dmi/id/product_name}" 2>/dev/null)
  [[ $product_name =~ MacBookPro13,[23]|MacBookPro14,[23] ]]
}

t1_touchbar_disp_installed() {
  [[ -f "$(t1_touchbar_disp_rule_dest)" ]]
}

t1_touchbar_disp_install() {
  local dest
  dest=$(t1_touchbar_disp_rule_dest)
  sudo mkdir -p "$(dirname "$dest")"
  sudo cp -f "${OMARCHY_PATH:-/usr/share/omarchy}/default/udev/apple-t1-touchbar-disp.rules" "$dest"
  sudo udevadm control --reload
}
