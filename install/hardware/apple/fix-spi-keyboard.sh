# Detect MacBook models that need SPI keyboard modules
product_name="$(cat /sys/class/dmi/id/product_name 2>/dev/null)"
if [[ $product_name =~ MacBook[89],1|MacBook1[02],1|MacBookPro13,[123]|MacBookPro14,[123] ]]; then
  echo "Detected MacBook with SPI keyboard"

  # Modern kernels already ship applespi. The old all-in-one DKMS package fails
  # to build on Linux 7 and conflicts with the separate T1 Touch Bar driver.
  in_tree_applespi=$(find /usr/lib/modules -path '*/kernel/drivers/input/keyboard/applespi.ko*' -print -quit)
  if [[ -z $in_tree_applespi ]]; then
    omarchy-pkg-add macbook12-spi-driver-dkms
  fi
  sudo mkdir -p /etc/mkinitcpio.conf.d
  if [[ $product_name == "MacBook8,1" ]]; then
    echo "MODULES=(applespi spi_pxa2xx_platform spi_pxa2xx_pci)" | \
      sudo tee /etc/mkinitcpio.conf.d/macbook_spi_modules.conf >/dev/null
  else
    echo "MODULES=(applespi intel_lpss_pci spi_pxa2xx_platform)" | \
      sudo tee /etc/mkinitcpio.conf.d/macbook_spi_modules.conf >/dev/null
  fi
fi
