# Detect MacBook models that need SPI keyboard modules
if [[ "$(cat /sys/class/dmi/id/product_name 2>/dev/null)" =~ MacBook[89],1|MacBook1[02],1|MacBookPro13,[123]|MacBookPro14,[123] ]]; then
  echo "Detected MacBook with SPI keyboard"

  sudo pacman -S --noconfirm --needed macbook12-spi-driver-dkms
  case "$(cat /sys/class/dmi/id/product_name 2>/dev/null)" in
    MacBook8,1)
      echo "MODULES=(applespi spi_pxa2xx_platform spi_pxa2xx_pci)" | sudo tee /etc/mkinitcpio.conf.d/macbook_spi_modules.conf >/dev/null
      ;;
    MacBook9,1|MacBook1[02],1|MacBookPro13,1|MacBookPro13,2|MacBookPro13,3|MacBookPro14,1|MacBookPro14,2|MacBookPro14,3)
      echo "MODULES=(applespi intel_lpss_pci spi_pxa2xx_platform)" | sudo tee /etc/mkinitcpio.conf.d/macbook_spi_modules.conf >/dev/null
      ;;
  esac
fi
