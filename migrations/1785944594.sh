echo "Update T2 Mac suspend, Touch Bar, and fan defaults"

if ! lspci -nn | grep "106b:180[12]" >/dev/null; then
  exit 0
fi

limine_conf="${OMARCHY_T2_LIMINE_CONF:-/etc/limine-entry-tool.d/t2-mac.conf}"
fan_conf="${OMARCHY_T2_FAN_CONF:-/etc/t2fand.conf}"
running_cmdline="${OMARCHY_T2_RUNNING_CMDLINE:-/proc/cmdline}"
repair_marker="${OMARCHY_T2_REPAIR_MARKER:-/var/lib/omarchy/migrations/1785944594}"
needs_limine_rebuild=0

if [[ -f $limine_conf ]] && grep -q 'pcie_ports=compat' "$limine_conf"; then
  sudo sed -i \
    's/pcie_ports=compat/pm_async=off mem_sleep_default=deep/' \
    "$limine_conf"
  needs_limine_rebuild=1
fi

# t2fanrd reads one section per detected fan and fails when a section is
# missing. Extra sections are ignored, so this also remains safe on one-fan
# models.
if [[ -f $fan_conf ]] && ! grep -Eq '^[[:space:]]*\[Fan2\][[:space:]]*$' "$fan_conf"; then
  sudo tee -a "$fan_conf" >/dev/null <<'EOF'

[Fan2]
low_temp=55
high_temp=75
speed_curve=linear
always_full_speed=false
EOF
fi

# The kernel's built-in Boot Camp-style Touch Bar works without tiny-dfr. The
# optional daemon holds stale device descriptors across suspend with t2bce.
if omarchy-pkg-present tiny-dfr; then
  sudo systemctl disable --now tiny-dfr.service || true
  omarchy-pkg-drop tiny-dfr
fi

# The current kernel keeps its old command line until reboot. Record a
# successful machine-wide rebuild so another user's migration does not repeat
# it before then, while a missing marker still retries an interrupted rebuild.
if [[ -f $limine_conf ]] &&
  [[ ! -e $repair_marker ]] &&
  grep -q 'pm_async=off' "$limine_conf" &&
  grep -q 'mem_sleep_default=deep' "$limine_conf" &&
  { [[ ! -r $running_cmdline ]] ||
    ! grep -Eq '(^| )pm_async=off( |$)' "$running_cmdline" ||
    ! grep -Eq '(^| )mem_sleep_default=deep( |$)' "$running_cmdline"; }; then
  needs_limine_rebuild=1
fi

if (( needs_limine_rebuild )); then
  sudo limine-mkinitcpio
  sudo install -Dm644 /dev/null "$repair_marker"
fi
