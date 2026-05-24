# Detect MacBook models that need SPI keyboard modules
product_name="$(cat /sys/class/dmi/id/product_name 2>/dev/null)"
if [[ $product_name =~ MacBook[89],1|MacBook1[02],1|MacBookPro13,[123]|MacBookPro14,[123] ]]; then
  echo "Detected MacBook with SPI keyboard"

  omarchy-pkg-add macbook12-spi-driver-dkms
  mkdir -p /etc/mkinitcpio.conf.d
  if [[ $product_name == "MacBook8,1" ]]; then
    echo "MODULES=(applespi spi_pxa2xx_platform spi_pxa2xx_pci)" > \
      /etc/mkinitcpio.conf.d/macbook_spi_modules.conf
  else
    echo "MODULES=(applespi intel_lpss_pci spi_pxa2xx_platform)" > \
      /etc/mkinitcpio.conf.d/macbook_spi_modules.conf
  fi
fi
