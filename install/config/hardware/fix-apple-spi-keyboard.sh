OMARCHY_DESCRIPTION="MacBook SPI Keyboard Support"

should_run() {
  [[ "$(cat /sys/class/dmi/id/product_name 2>/dev/null)" =~ MacBook12,1|MacBookPro13,[123]|MacBookPro14,[123] ]]
}

omarchy_install() {
  should_run || return 0

  echo "Detected MacBook with SPI keyboard"
  sudo pacman -S --noconfirm --needed macbook12-spi-driver-dkms
  echo "MODULES=(applespi intel_lpss_pci spi_pxa2xx_platform)" | sudo tee /etc/mkinitcpio.conf.d/macbook_spi_modules.conf >/dev/null
}

omarchy_verify() {
  should_run || return 2  # Return 2 to indicate "not applicable"

  # Check if driver is installed
  pacman -Q macbook12-spi-driver-dkms &>/dev/null || add_error "MacBook SPI driver not installed"

  # Check if mkinitcpio config exists
  [[ -f /etc/mkinitcpio.conf.d/macbook_spi_modules.conf ]] || add_error "MacBook SPI modules config missing"
}
