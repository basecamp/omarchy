echo "Force SPI PIO on MacBook8,1 so the built-in keyboard works"

# The install-time leaf already loads applespi for this model, but that is not
# enough: DesignWare DMA on 00:15.0 never completes GSPI transfers, so the
# keyboard and trackpad time out until the controller is forced into PIO.
# See install/hardware/apple/fix-spi-keyboard.sh.
product="${OMARCHY_MACBOOK81_DMI_PRODUCT:-/sys/class/dmi/id/product_name}"
limine_conf="${OMARCHY_MACBOOK81_LIMINE_CONF:-/etc/limine-entry-tool.d/macbook81-spi-pio.conf}"
repair_marker="${OMARCHY_MACBOOK81_REPAIR_MARKER:-/var/lib/omarchy/migrations/1788318101}"
running_cmdline="${OMARCHY_MACBOOK81_RUNNING_CMDLINE:-/proc/cmdline}"

product_name="$(cat "$product" 2>/dev/null || true)"
if [[ $product_name != "MacBook8,1" ]]; then
  exit 0
fi

needs_limine_rebuild=0

if [[ ! -f $limine_conf ]] || ! grep -q 'initcall_blacklist=dw_pci_driver_init' "$limine_conf"; then
  sudo mkdir -p "$(dirname "$limine_conf")"
  sudo tee "$limine_conf" >/dev/null <<'EOF'
# MacBook8,1: DesignWare DMA never completes GSPI transfers.
KERNEL_CMDLINE[default]+=" initcall_blacklist=dw_pci_driver_init mem_sleep_default=s2idle"
EOF
  needs_limine_rebuild=1
fi

# The current kernel keeps its old command line until reboot. Record a
# successful machine-wide rebuild so another user's migration does not repeat
# it before then, while a missing marker still retries an interrupted rebuild.
if [[ -f $limine_conf ]] &&
  [[ ! -e $repair_marker ]] &&
  grep -q 'initcall_blacklist=dw_pci_driver_init' "$limine_conf" &&
  { [[ ! -r $running_cmdline ]] ||
    ! grep -Eq '(^| )initcall_blacklist=dw_pci_driver_init( |$)' "$running_cmdline"; }; then
  needs_limine_rebuild=1
fi

if (( needs_limine_rebuild )); then
  sudo limine-mkinitcpio
  sudo install -Dm644 /dev/null "$repair_marker"
fi
