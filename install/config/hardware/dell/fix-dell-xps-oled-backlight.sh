# Display backlight fix for Dell XPS OLED Panther Lake laptops.
#
# The affected LG OLED panel accepts intel_backlight sysfs writes but only
# applies them through the VESA DPCD backlight interface.

if omarchy-hw-dell-xps-oled; then
  sudo mkdir -p /etc/limine-entry-tool.d
  cat <<EOF | sudo tee /etc/limine-entry-tool.d/dell-xps-oled-backlight.conf >/dev/null
# Dell XPS OLED display backlight fix
KERNEL_CMDLINE[default]+=" xe.enable_dpcd_backlight=1"
EOF
fi
