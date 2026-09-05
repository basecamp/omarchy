echo "Install the CS8409 speaker driver on pre-T2 Macs"

# 2016–2017 MacBook Pros and 2017–2019 iMacs with CS8409. T2 and other
# Apple hardware is unchanged.
if ! omarchy-hw-apple-cs8409; then
  exit 0
fi

omarchy-pkg-add linux-headers snd-hda-macbookpro-dkms
