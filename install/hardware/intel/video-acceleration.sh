# This installs hardware video acceleration for Intel GPUs.
#
# GPU generation can't be reliably told apart from the lspci name alone: "HD
# Graphics" is Intel's marketing name for both Gen7 (Ivy Bridge, needs the i965
# driver) and Gen8+ (Broadwell and later, needs iHD), and some older
# generations (Ironlake, Sandy Bridge, Haswell-ULT) don't say "HD Graphics" or
# "gma" at all, so they matched neither branch here and got no driver.
# Rather than chase the naming with a generation table, install both drivers;
# libva probes them in order at runtime and uses whichever one initializes for
# the GPU it finds, so this is correct on every generation without a table.
if lspci | grep -iE 'VGA compatible controller|3D controller|Display controller' | grep -qi 'intel'; then
  omarchy-pkg-add intel-media-driver libva-intel-driver libvpl vpl-gpu-rt
fi
