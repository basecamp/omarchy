echo "Resize zram to match the shipped config"

# 90-omarchy.conf changed the device size. The migration that first applied the
# zram tuning is one-shot, so machines that already ran it have the new file on
# disk and the old device still running; nothing would pick the size up until
# something else rebooted them.

zram_disksize=${OMARCHY_ZRAM_DISKSIZE:-/sys/block/zram0/disksize}
swaps=${OMARCHY_SWAPS:-/proc/swaps}

# The size is an expression, and the generator is the only thing that evaluates
# it. Ask it what the shipped config comes to rather than repeating the
# arithmetic here, where the two would drift apart on the next tuning change.
units=$(mktemp -d)
trap 'rm -rf "$units"' EXIT
desired_mb=$(/usr/lib/systemd/system-generators/zram-generator "$units" 2>&1 |
  grep -oP '/dev/zram0 with \K[0-9]+') || true

actual_bytes=$(cat "$zram_disksize" 2>/dev/null) || actual_bytes=0

# A device already at the right size needs neither a restart nor a reboot,
# whether an earlier boot picked the config up or another user got here first.
if [[ -n $desired_mb && $actual_bytes == $((desired_mb * 1024 * 1024)) ]]; then
  exit 0
fi

if sudo systemctl daemon-reload; then
  # Resizing swaps the device off first, which faults every stored page back
  # into memory. That's only cheap while it's empty, so a device under
  # pressure keeps its old size until the next boot.
  zram_used=$(awk '$1 == "/dev/zram0" {print $4}' "$swaps")

  # No row at all means the device is not swap right now, and that covers two
  # unlike situations. A device that doesn't exist yet is the one worth acting
  # on: the restart brings it up against the config daemon-reload just picked
  # up. A device that exists but is swapped off is not, because the restart
  # resets it first, and reset returns EBUSY for as long as anything still
  # holds it open. That leaves a "Job failed" from systemd in the migration
  # output and still ends up asking for the reboot, so go straight there.
  if [[ -n $zram_used || ! -e $zram_disksize ]] &&
    [[ ${zram_used:-0} == 0 ]] &&
    sudo systemctl restart dev-zram0.swap; then
    exit 0
  fi
fi

omarchy-state set reboot-required
