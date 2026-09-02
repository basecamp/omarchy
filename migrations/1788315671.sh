echo "Fix T2 Mac suspend: s2idle, d3cold, and brcmfmac"

if ! lspci -nn | grep "106b:180[12]" >/dev/null; then
  exit 0
fi

limine_conf="${OMARCHY_T2_LIMINE_CONF:-/etc/limine-entry-tool.d/t2-mac.conf}"
sleep_conf="${OMARCHY_T2_SLEEP_CONF:-/etc/systemd/sleep.conf.d/t2-suspend.conf}"
suspend_unit="${OMARCHY_T2_SUSPEND_UNIT:-/etc/systemd/system/omarchy-suspend-t2.service}"
running_cmdline="${OMARCHY_T2_RUNNING_CMDLINE:-/proc/cmdline}"
repair_marker="${OMARCHY_T2_S2IDLE_MARKER:-/var/lib/omarchy/migrations/1788315671}"
needs_limine_rebuild=0

# 1785944594 moved T2 Macs to mem_sleep_default=deep. These machines do not
# return from deep: suspend is entered, the kernel writes nothing further, and
# the machine resets without leaving a pstore log. Move them back to s2idle.
if [[ -f $limine_conf ]] && grep -q 'mem_sleep_default=deep' "$limine_conf"; then
  sudo sed -i 's/mem_sleep_default=deep/mem_sleep_default=s2idle/' "$limine_conf"
  needs_limine_rebuild=1
fi

# systemd only consults mem_sleep_default when it writes "mem", so pin the
# state directly rather than relying on the command line alone.
if [[ ! -f $sleep_conf ]] || ! grep -Eq '^[[:space:]]*SuspendState=freeze[[:space:]]*$' "$sleep_conf"; then
  sudo mkdir -p "$(dirname "$sleep_conf")"
  sudo tee "$sleep_conf" >/dev/null <<'EOF'
[Sleep]
SuspendState=freeze
EOF
fi

# brcmfmac times out entering D3 and aborts the suspend outright; the Apple
# NVMe controller and T2 bridges enter d3cold and cannot be recovered on
# longer sleeps. Both apply to the apple-bce and t2bce stacks alike.
if [[ ! -f $suspend_unit ]]; then
  sudo mkdir -p "$(dirname "$suspend_unit")"
  sudo tee "$suspend_unit" >/dev/null <<'EOF'
[Unit]
Description=Prepare T2 Mac peripherals for suspend
Before=sleep.target
StopWhenUnneeded=yes

[Service]
User=root
Type=oneshot
RemainAfterExit=yes
ExecStart=/bin/bash -c 'for dev in /sys/bus/pci/devices/*/; do vendor=$(cat "$dev/vendor" 2>/dev/null); device=$(cat "$dev/device" 2>/dev/null); if [[ "$vendor" == "0x106b" ]] && [[ "$device" == "0x2005" || "$device" == "0x1801" || "$device" == "0x1802" ]]; then echo 0 > "$dev/d3cold_allowed" 2>/dev/null; fi; done; rmmod brcmfmac_wcc 2>/dev/null; rmmod brcmfmac 2>/dev/null; true'
ExecStop=/bin/bash -c 'modprobe brcmfmac'

[Install]
WantedBy=sleep.target
EOF
  sudo systemctl daemon-reload
  sudo systemctl enable omarchy-suspend-t2.service
fi

# The running kernel keeps its old command line until reboot. Record a
# successful machine-wide rebuild so another user's migration does not repeat
# it before then, while a missing marker still retries an interrupted rebuild.
if [[ -f $limine_conf ]] &&
  [[ ! -e $repair_marker ]] &&
  grep -q 'mem_sleep_default=s2idle' "$limine_conf" &&
  { [[ ! -r $running_cmdline ]] ||
    ! grep -Eq '(^| )mem_sleep_default=s2idle( |$)' "$running_cmdline"; }; then
  needs_limine_rebuild=1
fi

if ((needs_limine_rebuild)); then
  sudo limine-mkinitcpio
  sudo install -Dm644 /dev/null "$repair_marker"
fi
