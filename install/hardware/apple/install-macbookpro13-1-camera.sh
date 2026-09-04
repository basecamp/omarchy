if omarchy-hw-match '^MacBookPro13,1$'; then
  echo "Installing MacBookPro13,1 FaceTime HD camera support"
  omarchy-pkg-add facetimehd-dkms facetimehd-firmware
fi
