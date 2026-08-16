# 2016–2017 MacBook Pros use CS8409 HDA. The in-tree codec driver leaves
# the speaker amps unprogrammed; snd-hda-macbookpro-dkms is the Apple path.

if omarchy-hw-apple-cs8409; then
  echo "Detected MacBook with Cirrus CS8409 audio"

  omarchy-pkg-add linux-headers snd-hda-macbookpro-dkms
fi
