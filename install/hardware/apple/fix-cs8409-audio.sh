# The 2016-2017 MacBook Pros drive their speakers through a Cirrus CS8409 HDA
# bridge paired with a CS42L83 codec and external amplifiers switched on over
# GPIO/I2C. The in-tree snd_hda_codec_cs8409 driver binds the codec but never
# enables those lines, so the card enumerates and PipeWire reports a healthy
# analog-stereo sink sitting on analog-output-speaker while nothing comes out.
# The tell is /proc/asound/card0/codec#0 reporting "GPIO: io=8" with every IO[n]
# at enable=0, and amixer exposing only a PCM control with no Speaker or
# Headphone jacks.
#
# snd-hda-macbookpro-dkms-git replaces the in-tree module with a build that
# programs the amplifiers and brings up the CS42L83. T2 Macs take a different
# audio path and are handled by fix-t2.sh; every model matched here predates it.
#
# linux-headers is installed alongside the driver deliberately. Arch's DKMS
# pacman hook discovers kernels by globbing usr/lib/modules/*/build, so with no
# headers installed it finds nothing to build against, builds nothing and exits
# quietly. That leaves an installed package, an empty `dkms status` and silent
# speakers, which reads like the driver not supporting the model.
product_name="$(cat /sys/class/dmi/id/product_name 2>/dev/null)"
if [[ $product_name =~ MacBookPro13,[123]|MacBookPro14,[123] ]]; then
  echo "Detected MacBook with Cirrus CS8409 audio"

  omarchy-pkg-add linux-headers snd-hda-macbookpro-dkms-git
fi
