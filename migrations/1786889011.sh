echo "Install the CS8409 MacBook speaker driver"

# 2016–2017 MacBook Pros only. T2 and other Apple hardware is unchanged.
if ! omarchy-hw-apple-cs8409; then
  exit 0
fi

omarchy-pkg-add linux-headers snd-hda-macbookpro-dkms
