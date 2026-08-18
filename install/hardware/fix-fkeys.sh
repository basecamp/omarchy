# hid_apple fnmode=3 (auto) already uses fkeysfirst for boards the kernel flags
# APPLE_IS_NON_APPLE (Keychron, SONiX, and similar). Lofree Flow84 is not on
# that list: in Mac mode it binds hid_apple and otherwise keeps media keys on
# the top row, so non-Apple machines still need fnmode=2.
#
# Do not write that globally. On genuine Apple/T2 hardware it switches MacBook
# internals and Magic Keyboard from fkeyslast (media/brightness without Fn) to
# fkeysfirst, which contradicts the Mac docs.

dmi_vendor="${OMARCHY_HID_APPLE_DMI_VENDOR:-/sys/class/dmi/id/sys_vendor}"
conf="${OMARCHY_HID_APPLE_CONF:-/etc/modprobe.d/hid_apple.conf}"
sys_vendor="$(cat "$dmi_vendor" 2>/dev/null || true)"

if [[ $sys_vendor == Apple* ]]; then
  if [[ -f $conf && $(<"$conf") == "options hid_apple fnmode=2" ]]; then
    sudo rm -f "$conf"
  fi
elif [[ ! -f $conf ]]; then
  sudo mkdir -p "$(dirname "$conf")"
  echo "options hid_apple fnmode=2" | sudo tee "$conf" >/dev/null
fi
