if omarchy-hw-match '^MacBookPro13,1$'; then
  echo "Installing MacBookPro13,1 Cirrus audio support"
  omarchy-pkg-add snd-hda-macbookpro-dkms
fi
