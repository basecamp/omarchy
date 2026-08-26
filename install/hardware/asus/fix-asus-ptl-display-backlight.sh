# Display backlight fix for ASUS Panther Lake / Xe3 iGPU laptops.
# Enabled only for ExpertBook B9406 and Zenbook UX5406AA for now.
# Other models need confirmation whether the issue exists there too.
#
# Confirmed NOT to apply to the ROG Zephyrus G14 GU405AR: it shows the same
# symptom (empty panel EDID, intel_backlight writes with no visible effect),
# but xe.enable_dpcd_backlight=1 leaves that panel black rather than fixing it.
# Its panel does implement DPCD/AUX brightness -- 0x0701 bit0 (TCON backlight
# adjustment) and 0x0702 bit1 (AUX set) are both set, with an 11-bit range from
# 0x0724 -- and driving 0x0721/0x0722/0x0723 over the AUX channel from
# userspace dims it correctly. So the symptom matching is not sufficient on its
# own; do not widen the gate to a model without testing it boots.
#
# The panel's EDID on eDP-1 reads as empty, so xe takes backlight type from
# VBT (which says PWM) but the panel actually wants DPCD AUX backlight.
# Without xe.enable_dpcd_backlight=1, intel_backlight sysfs writes succeed
# but produce no visible change; brightness is effectively binary.

if omarchy-hw-asus-expertbook-b9406 || omarchy-hw-asus-zenbook-ux5406aa; then
  sudo mkdir -p /etc/limine-entry-tool.d
  sudo tee /etc/limine-entry-tool.d/asus-ptl-display-backlight.conf >/dev/null <<'EOF'
# ASUS Panther Lake display backlight fix
KERNEL_CMDLINE[default]+=" xe.enable_dpcd_backlight=1"
EOF
fi
