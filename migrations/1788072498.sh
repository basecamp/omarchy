echo "Use s2idle suspend on T2 Macs with a discrete GPU"

# grep -q would stop reading before lspci finishes writing, and pipefail reads
# the resulting SIGPIPE as "no T2 hardware" (#6608).
if ! lspci -nn | grep "106b:180[12]" >/dev/null; then
  exit 0
fi

# Deep suspend (S3) is right on integrated-only T2 Macs, but it cannot complete
# where a discrete GPU is present: amdgpu fails its noirq suspend ("GPU mode1
# reset failed", pci_pm_suspend_noirq -22), the whole transition unwinds, and
# systemd retries with s2idle anyway. The doomed pass also rewrites four Apple
# EFI secure-boot variables every cycle. Integrated-only models keep deep.
if ! omarchy-hw-hybrid-gpu; then
  exit 0
fi

limine_conf="${OMARCHY_T2_LIMINE_CONF:-/etc/limine-entry-tool.d/t2-mac.conf}"
running_cmdline="${OMARCHY_T2_RUNNING_CMDLINE:-/proc/cmdline}"
repair_marker="${OMARCHY_T2_S2IDLE_MARKER:-/var/lib/omarchy/migrations/1788072498}"
needs_limine_rebuild=0

if [[ -f $limine_conf ]] && grep -q 'mem_sleep_default=deep' "$limine_conf"; then
  sudo sed -i \
    's/mem_sleep_default=deep/mem_sleep_default=s2idle/' \
    "$limine_conf"
  needs_limine_rebuild=1
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

if (( needs_limine_rebuild )); then
  sudo limine-mkinitcpio
  sudo install -Dm644 /dev/null "$repair_marker"
fi
