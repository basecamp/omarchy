# Detect MacBook models that need SPI keyboard modules
product_name="$(cat /sys/class/dmi/id/product_name 2>/dev/null)"
if [[ $product_name =~ MacBook[89],1|MacBook1[02],1|MacBookPro13,[123]|MacBookPro14,[123] ]]; then
  echo "Detected MacBook with SPI keyboard"

  if [[ $product_name == "MacBook8,1" ]]; then
    # MacBook8,1 (12", Early 2015) — Wildcat Point GSPI (8086:9ce6) quirk:
    #
    # The DesignWare DMA hardware handshake signal from the GSPI never asserts
    # on this hardware, so all DMA-based SPI transfers stall indefinitely.
    # macbook12-spi-driver-dkms also fails to build on kernel 6.x due to
    # removed APIs (input-polldev etc.).
    #
    # Fix: install a patched spi_pxa2xx_pci that forces PIO mode for this PCI
    # ID only (enable_dma=0), plus irqpoll so the SPI IRQ handler is polled
    # unconditionally. This restores the in-tree applespi keyboard and trackpad.
    #
    # See: https://github.com/basecamp/omarchy/issues/1954

    omarchy-pkg-add dkms linux-headers

    local dkms_src="/usr/src/spi-pxa2xx-pci-nodma-1.0"
    sudo mkdir -p "$dkms_src"
    sudo cp "$(omarchy-config-dir)/hardware/apple/macbook8-spi-pxa2xx-nodma/"* "$dkms_src/"

    sudo dkms add spi-pxa2xx-pci-nodma/1.0
    sudo dkms build spi-pxa2xx-pci-nodma/1.0
    sudo dkms install spi-pxa2xx-pci-nodma/1.0

    # Blacklist the in-tree module; our patched version registers the same
    # PCI driver name so the GSPI binds to it automatically on next boot.
    echo "blacklist spi_pxa2xx_pci" | sudo tee /etc/modprobe.d/macbook8-spi-nodma.conf >/dev/null
    echo "install spi_pxa2xx_pci /bin/true" | sudo tee -a /etc/modprobe.d/macbook8-spi-nodma.conf >/dev/null

    # irqpoll: poll all IRQ handlers unconditionally so the SPI PIO IRQ
    # (IRQ 21, IO-APIC) is serviced even when the hardware doesn't assert it.
    sudo mkdir -p /etc/limine-entry-tool.d
    cat <<'EOF' | sudo tee /etc/limine-entry-tool.d/macbook8-spi.conf >/dev/null
# MacBook8,1 SPI keyboard/trackpad fix
# irqpoll: required because GSPI IRQ 21 and DMA IRQ 20 never fire from hardware.
# Without it, PIO-mode SPI transfers stall waiting for an interrupt that never arrives.
KERNEL_CMDLINE[default]+=" irqpoll"
EOF

    echo "MODULES=(spi_pxa2xx_pci_nodma applespi spi_pxa2xx_platform)" | \
      sudo tee /etc/mkinitcpio.conf.d/macbook_spi_modules.conf >/dev/null

  else
    omarchy-pkg-add macbook12-spi-driver-dkms
    echo "MODULES=(applespi intel_lpss_pci spi_pxa2xx_platform)" | \
      sudo tee /etc/mkinitcpio.conf.d/macbook_spi_modules.conf >/dev/null
  fi
fi
