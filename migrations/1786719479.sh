echo "Install the CS4208 speaker driver on 12-inch MacBooks"

# Fresh installs get this from install/hardware/apple/fix-cs4208-audio.sh.
# Existing MacBook9,1 / MacBook10,1 installs still have silent speakers:
# mainline detects the codec and PipeWire plays, but the speaker amp is never
# enabled. Skip machines that already have the packaged module or the same
# DKMS driver installed by hand.

product_name="${OMARCHY_MACBOOK12_AUDIO_MODEL:-$(cat /sys/class/dmi/id/product_name 2>/dev/null)}"
if [[ $product_name != "MacBook9,1" && $product_name != "MacBook10,1" ]]; then
  exit 0
fi

if omarchy-pkg-present macbook12-audio-driver-dkms; then
  exit 0
fi

if dkms status 2>/dev/null | grep -q '^macbook12-audio/'; then
  exit 0
fi

omarchy-pkg-add macbook12-audio-driver-dkms
omarchy-state set reboot-required
