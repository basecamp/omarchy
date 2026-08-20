# Enable speakers on 12-inch MacBooks (MacBook9,1 / 2016 and MacBook10,1 / 2017).
# Mainline snd_hda_codec_cs420x detects the CS4208 but never runs the macOS
# init that powers the speaker amplifier, so PipeWire plays to a silent analog
# path. The out-of-tree module replays that init.
# MacBook8,1 (2015) is not supported by this driver.
# https://github.com/leifliddy/macbook12-audio-driver
# https://github.com/basecamp/omarchy/issues/2101

product_name="${OMARCHY_MACBOOK12_AUDIO_MODEL:-$(cat /sys/class/dmi/id/product_name 2>/dev/null)}"
if [[ $product_name == "MacBook9,1" || $product_name == "MacBook10,1" ]]; then
  echo "Detected 12-inch MacBook with CS4208 audio"

  omarchy-pkg-add macbook12-audio-driver-dkms
fi
