# Pre-T2 Macs with a Cirrus CS8409 HDA bridge (2016–2017 MacBook Pros and
# 2017–2019 iMacs) leave the speaker amps unprogrammed under the in-tree
# codec driver. snd-hda-macbookpro-dkms is the Apple path that enables them.

if omarchy-hw-apple-cs8409; then
  echo "Detected Mac with Cirrus CS8409 audio"

  omarchy-pkg-add linux-headers snd-hda-macbookpro-dkms
fi
