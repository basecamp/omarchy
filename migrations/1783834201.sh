echo "Install sof-firmware for all Intel SOF audio DSP platforms (Arrow Lake, Meteor Lake, etc.)"

# Intel SOF platforms beyond Panther Lake and Wildcat Lake (Arrow Lake, Meteor
# Lake, Tiger Lake, Alder Lake) were not covered by the original sof-firmware
# install guard. Without sof-firmware the DSP fails to boot and PipeWire exposes
# only a Dummy Output. Install it now for all qualifying Intel systems.
#
if omarchy-hw-intel-sof; then
  firmware_missing=false
  if omarchy-pkg-missing sof-firmware; then
    firmware_missing=true
  fi

  omarchy-pkg-add sof-firmware
  sudo pacman -D --asexplicit sof-firmware >/dev/null

  if [[ $firmware_missing == "true" ]]; then
    omarchy-state set reboot-required
  fi
fi
