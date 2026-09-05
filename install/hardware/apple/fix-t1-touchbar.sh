# MacBookPro13,3 always carries Apple's T1 iBridge, but mainline's Touch Bar
# support is T2-only. Install the package-backed, freeze-safe T1 driver when
# the production iBridge USB identity is present. The package pins
# skip_acpi_power=1 before DKMS can load the module and never rebinds USB live.
: "${OMARCHY_PATH:=/usr/share/omarchy}"
: "${OMARCHY_INSTALL:=$OMARCHY_PATH/install}"
# shellcheck source=t1-touchbar.sh
source "$OMARCHY_INSTALL/hardware/apple/t1-touchbar.sh"

if t1_touchbar_needed; then
  echo "Detected MacBookPro13,3 T1 iBridge; installing Touch Bar support"
  omarchy-pkg-add apple-ib-drv-dkms
fi
