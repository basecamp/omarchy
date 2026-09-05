echo "Remove the obsolete MacBook SPI keyboard DKMS package"

# applespi is mainlined (it ships with the linux package), so the out-of-tree
# driver cannot build on current kernels: its include was removed in kernel
# 6.12 and the DKMS build fails on every kernel update once linux-headers is
# present. The initramfs drop-in written by
# install/hardware/apple/fix-spi-keyboard.sh loads the in-tree module instead,
# so the package is pure failure surface. Idempotent: nothing happens when the
# package is not installed.
if omarchy-pkg-present macbook12-spi-driver-dkms; then
  omarchy-pkg-drop macbook12-spi-driver-dkms
fi
