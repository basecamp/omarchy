# Install resume sleep-hook for Razer Blade laptops with the Cypress
# 06CB:CDA3 I2C HID touchpad on AMD's AMDI0010 controller. After S3/S4
# the touchpad returns with stale state and click stops working; the
# hook reloads hid_multitouch on every resume to recover it.

if grep -qi "Razer" /sys/class/dmi/id/sys_vendor 2>/dev/null \
   && compgen -G "/sys/bus/platform/devices/AMDI0010*" >/dev/null \
   && compgen -G "/sys/bus/hid/devices/*06CB:CDA3*" >/dev/null; then
  sudo mkdir -p /usr/lib/systemd/system-sleep
  sudo install -m 0755 -o root -g root "$OMARCHY_PATH/default/systemd/system-sleep/fix-razer-amd-trackpad" /usr/lib/systemd/system-sleep/
fi
