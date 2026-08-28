# Brightness fix for the OLED Zephyrus G14 (GA403), whose GPU MUX can route the
# internal panel straight to the dGPU.
#
# Scoped to GA403 for now. Other MUX-capable ROG models need confirmation: this
# only bites panels that take their brightness over DP AUX from the iGPU driver,
# and a PWM-backlit ROG in the same position may well be fine.
#
# In the discrete position (gpu_mux_mode 0) the panel hangs off the NVIDIA GPU,
# which reports "ACPI reported no NVIDIA native backlight available" and falls
# back to an ACPI/EC interface this firmware only half-implements. A backlight
# device still registers and still accepts writes, but the panel never responds,
# so the machine is stuck at whatever brightness it booted at. Hybrid puts the
# panel back on amdgpu, where amdgpu_bl* drives it over DP AUX.
#
# Firmware applies the attribute at the next POST and install is followed by a
# reboot, so queue the change rather than trying to switch a live MUX.

if omarchy-hw-match "GA403"; then
  for mux_attr in /sys/class/firmware-attributes/asus-armoury/attributes/gpu_mux_mode/current_value \
    /sys/devices/platform/asus-nb-wmi/gpu_mux_mode; do
    if [[ -e $mux_attr ]]; then
      if [[ $(cat "$mux_attr") == "0" ]]; then
        echo 1 | sudo tee "$mux_attr" >/dev/null
      fi
      break
    fi
  done
fi
