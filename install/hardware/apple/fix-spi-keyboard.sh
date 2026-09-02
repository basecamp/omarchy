# Detect MacBook models that need SPI keyboard modules
product_name="$(cat /sys/class/dmi/id/product_name 2>/dev/null)"
if [[ $product_name =~ MacBook[89],1|MacBook1[02],1|MacBookPro13,[123]|MacBookPro14,[123] ]]; then
  echo "Detected MacBook with SPI keyboard"

  omarchy-pkg-add macbook12-spi-driver-dkms
  sudo mkdir -p /etc/mkinitcpio.conf.d
  if [[ $product_name == "MacBook8,1" ]]; then
    echo "MODULES=(applespi spi_pxa2xx_platform spi_pxa2xx_pci)" | \
      sudo tee /etc/mkinitcpio.conf.d/macbook_spi_modules.conf >/dev/null

    # The Wildcat Point GSPI controller (00:15.4) does transfers through the
    # companion DesignWare DMA engine (00:15.0). On this board those DMA
    # transfers never complete: applespi times out with -110 and IRQ 21 stays
    # at zero. dw_dmac_pci is builtin, so it cannot be blacklisted as a module.
    # Blacklisting its initcall forces spi-pxa2xx into PIO, which works.
    # Deep/S3 sleep then wedges the same SPI device until reboot; s2idle does not.
    sudo mkdir -p /etc/limine-entry-tool.d
    sudo tee /etc/limine-entry-tool.d/macbook81-spi-pio.conf >/dev/null <<'EOF'
# MacBook8,1: DesignWare DMA never completes GSPI transfers.
KERNEL_CMDLINE[default]+=" initcall_blacklist=dw_pci_driver_init mem_sleep_default=s2idle"
EOF
  else
    echo "MODULES=(applespi intel_lpss_pci spi_pxa2xx_platform)" | \
      sudo tee /etc/mkinitcpio.conf.d/macbook_spi_modules.conf >/dev/null
  fi
fi
