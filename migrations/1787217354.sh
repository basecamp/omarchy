echo "Cap intel_idle C-states on 2011 MacBook Airs to prevent idle hard-freeze"

limine_conf="${OMARCHY_SANDY_IDLE_LIMINE_CONF:-/etc/limine-entry-tool.d/apple-sandy-bridge-idle.conf}"
running_cmdline="${OMARCHY_RUNNING_CMDLINE:-/proc/cmdline}"
repair_marker="${OMARCHY_SANDY_IDLE_REPAIR_MARKER:-/var/lib/omarchy/migrations/1787217354}"

omarchy-hw-match "MacBookAir4," || exit 0

needs_rebuild=0

# Installs that predate install/hardware/apple/fix-sandy-bridge-idle.sh never
# got the drop-in from hardware setup.
if [[ ! -f $limine_conf ]]; then
  sudo install -Dm644 /dev/stdin "$limine_conf" <<'EOF'
# 2011 MacBook Air (Sandy Bridge) hard-locks when idling into deep C-states
KERNEL_CMDLINE[default]+=" intel_idle.max_cstate=1"
EOF
  needs_rebuild=1
fi

# The running kernel keeps its old command line until reboot, so a marker
# records the machine-wide rebuild instead: another user's migration must not
# repeat it before then, while a missing marker still retries an interrupted
# rebuild.
if [[ ! -e $repair_marker ]] &&
  { [[ ! -r $running_cmdline ]] ||
    ! grep -Eq '(^| )intel_idle\.max_cstate=1( |$)' "$running_cmdline"; }; then
  needs_rebuild=1
fi

if (( needs_rebuild )); then
  sudo limine-mkinitcpio
  sudo install -Dm644 /dev/null "$repair_marker"

  # Someone who already added the cap by hand (e.g. straight into
  # /etc/default/limine) is running fixed and only needed the drop-in baked in.
  if [[ ! -r $running_cmdline ]] ||
    ! grep -Eq '(^| )intel_idle\.max_cstate=1( |$)' "$running_cmdline"; then
    omarchy-state set reboot-required
  fi
fi
