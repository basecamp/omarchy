echo "Install the generation-correct Intel VAAPI driver"

# Existing installs could miss a driver entirely (Intel GPUs whose lspci name
# is not "HD Graphics" / "GMA") or get intel-media-driver on Haswell-class
# parts that need libva-intel-driver. Hybrid NVIDIA laptops still encode on
# the iGPU; screen recording then fails vaInitialize until the Intel package
# is present. Idempotent: omarchy-pkg-add is a no-op when the package is there.

driver=$(omarchy-hw-intel-vaapi-driver) || exit 0

if [[ $driver == intel-media-driver ]]; then
  omarchy-pkg-add intel-media-driver libvpl vpl-gpu-rt
else
  omarchy-pkg-add libva-intel-driver
fi
