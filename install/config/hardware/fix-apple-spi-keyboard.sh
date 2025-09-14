# Detect MacBook models that need SPI keyboard modules
if [[ "$(cat /sys/class/dmi/id/product_name 2>/dev/null)" =~ MacBook12,1|MacBookPro13,[123]|MacBookPro14,[123] ]]; then
  echo "Detected MacBook with SPI keyboard"

  sudo pacman -S --noconfirm --needed macbook12-spi-driver-dkms
  echo "MODULES=(applespi intel_lpss_pci spi_pxa2xx_platform)" | sudo tee /etc/mkinitcpio.conf.d/macbook_spi_modules.conf >/dev/null
fi
