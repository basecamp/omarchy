# Display backlight fix for ASUS Panther Lake / Xe3 iGPU laptops.
# Enabled only for ExpertBook B9406 and Zenbook UX5406AA for now.
# Other models need confirmation if the issue exists there too.
#
# The panel's EDID on eDP-1 reads as empty, so xe takes backlight type from
# VBT (which says PWM) but the panel actually wants DPCD AUX backlight.
# Without xe.enable_dpcd_backlight=1, intel_backlight sysfs writes succeed
# but produce no visible change; brightness is effectively binary.

if omarchy-hw-asus-expertbook-b9406 || omarchy-hw-asus-zenbook-ux5406aa; then
  sudo mkdir -p /etc/limine-entry-tool.d
  cat <<EOF | sudo tee /etc/limine-entry-tool.d/asus-ptl-display-backlight.conf >/dev/null
# ASUS Panther Lake display backlight fix
KERNEL_CMDLINE[default]+=" xe.enable_dpcd_backlight=1"
EOF
fi
