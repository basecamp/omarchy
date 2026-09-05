# 15" 2016–2017 MacBook Pros with a Radeon cannot resume from S3 or s2idle.
# Lock the lid, refuse sleep, and put the discrete GPU on POWER_SAVING so a
# closed lid does not cook the chassis. Keep BCM43602 out of PCI D3. The GPU
# stays bound.

if omarchy-hw-apple-mbp15-dgpu; then
  echo "Detected 15-inch MacBook Pro with Radeon; sleep does not resume"

  # shellcheck source=mbp15-dgpu.sh
  source "$OMARCHY_INSTALL/hardware/apple/mbp15-dgpu.sh"
  mbp15_apply
fi
