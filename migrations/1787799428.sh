echo "Install the generation-correct Intel VAAPI driver"

# Existing installs could miss a driver entirely (Intel GPUs whose lspci name
# is not "HD Graphics" / "GMA") or get intel-media-driver on Haswell-class
# parts that need libva-intel-driver. Hybrid NVIDIA laptops still encode on
# the iGPU; screen recording then fails vaInitialize until the Intel package
# is present. Idempotent: omarchy-pkg-add is a no-op when the package is there.
#
# A missing helper must not count as "no Intel GPU" — that would write the
# completion marker and never retry. Exit 1 so omarchy-migrate leaves it pending.

if ! command -v omarchy-hw-intel-vaapi-driver >/dev/null; then
  echo "omarchy-hw-intel-vaapi-driver is not on PATH" >&2
  exit 1
fi

# One package per line. Both iHD and i965 when an old iGPU sits next to a
# later Intel GPU — the display node still needs i965.
while IFS= read -r driver; do
  [[ -n $driver ]] || continue
  if [[ $driver == "intel-media-driver" ]]; then
    omarchy-pkg-add intel-media-driver libvpl vpl-gpu-rt
  elif [[ $driver == "libva-intel-driver" ]]; then
    omarchy-pkg-add libva-intel-driver
  fi
done < <(omarchy-hw-intel-vaapi-driver || true)
