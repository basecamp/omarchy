# This installs hardware video acceleration for Intel GPUs.
#
# Match by PCI ID, not the marketing name: Haswell often shows up as
# "4th Gen Core Processor Integrated Graphics Controller" with no "HD Graphics"
# in the string, so the old regex installed nothing. Hybrid Intel+NVIDIA
# laptops still encode on the iGPU that owns the display, so the Intel driver
# is required even when an NVIDIA VAAPI package is also present.
#
# Broadwell and later Core/Arc gens use intel-media-driver. GM45 through
# Haswell, plus CherryView/Braswell, use libva-intel-driver (i965). Pre-GM45
# chipset graphics have no package. A machine that needs both (Haswell iGPU
# plus a later Intel GPU) gets both packages. See omarchy-hw-intel-vaapi-driver.

while IFS= read -r driver; do
  [[ -n $driver ]] || continue
  if [[ $driver == "intel-media-driver" ]]; then
    omarchy-pkg-add intel-media-driver libvpl vpl-gpu-rt
  elif [[ $driver == "libva-intel-driver" ]]; then
    omarchy-pkg-add libva-intel-driver
  fi
done < <(omarchy-hw-intel-vaapi-driver || true)
