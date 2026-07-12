echo "Install sof-firmware for all Intel SOF audio DSP platforms (Arrow Lake, Meteor Lake, etc.)"

# Intel SOF platforms beyond Panther Lake and Wildcat Lake (Arrow Lake, Meteor
# Lake, Tiger Lake, Alder Lake) were not covered by the original sof-firmware
# install guard. Without sof-firmware the DSP fails to boot and PipeWire exposes
# only a Dummy Output. Install it now for all qualifying Intel systems.
#
# omarchy-pkg-add is idempotent — systems that already have the package are
# unaffected.

if omarchy-hw-intel-sof; then
  omarchy-pkg-add sof-firmware
fi
