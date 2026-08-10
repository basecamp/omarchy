# Display backlight fix for Dell XPS OLED laptops on Intel Panther Lake (Xe3).
# Enabled only for the LG panel matched by omarchy-hw-dell-xps-oled for now.
# Other panels need confirmation whether the issue exists there too.
#
# Without this, intel_backlight sysfs writes succeed and actual_brightness
# tracks them, but the panel stays at one brightness.
#
# The panel's EDID carries no HDR static metadata, so the kernel suggests
# enable_dpcd_backlight=3. Don't take that hint. 3 forces the Intel HDR
# interface, which this panel accepts writes on but never acts on: brightness
# arrives as nits in DPCD 0x354/0x355, yet 0x357 BRIGHTNESS_CONTROL_ENABLE
# stays clear. 1 selects the VESA DPCD interface, which does work -- 0x721
# reads 0x82 (AUX control mode plus PANEL_LUMINANCE_CONTROL_ENABLE), so the
# level rides the luminance path and 0x734 tracks sysfs in millinits.
#
# Note the driver is xe, not i915: the kernel's own hint names
# i915.enable_dpcd_backlight, the wrong module on Panther Lake.

if omarchy-hw-dell-xps-oled; then
  sudo mkdir -p /etc/limine-entry-tool.d
  sudo tee /etc/limine-entry-tool.d/dell-xps-oled-backlight.conf >/dev/null <<'EOF'
# Dell XPS OLED display backlight fix
KERNEL_CMDLINE[default]+=" xe.enable_dpcd_backlight=1"
EOF
fi
