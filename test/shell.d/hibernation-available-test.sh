#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT

sys_power="$tmp_dir/power"
swaps="$tmp_dir/swaps"
resume_conf="$tmp_dir/omarchy_resume.conf"

mkdir -p "$sys_power"

write_sleep_states() {
  printf '%s\n' "$1" >"$sys_power/state"
}

write_swaps() {
  {
    printf 'Filename\t\t\t\tType\t\tSize\t\tUsed\t\tPriority\n'
    printf '%s\n' "$@"
  } >"$swaps"
}

hibernation_available() {
  OMARCHY_SYS_POWER_PATH="$sys_power" \
    OMARCHY_SWAPS_PATH="$swaps" \
    OMARCHY_RESUME_CONF_PATH="$resume_conf" \
    "$ROOT/bin/omarchy-hibernation-available"
}

printf '%s\n' '6871947673' >"$sys_power/image_size"
write_sleep_states 'freeze mem disk'
write_swaps '/swap/swapfile                          file            62914556        0       0' \
  '/dev/zram0                              partition       8388604         0       100'
: >"$resume_conf"

hibernation_available || fail "hibernation is available with a resume config and swap the kernel will accept"
pass "hibernation is available with a resume config and swap the kernel will accept"

# The kernel lists "disk" only while it will accept a hibernation request, so a
# probe that ignores it offers a Hibernate entry that does nothing (#7730).
write_sleep_states 'freeze mem'

if hibernation_available; then
  fail "hibernation is unavailable when the kernel offers no disk sleep state"
fi
pass "hibernation is unavailable when the kernel offers no disk sleep state"

write_sleep_states 'freeze mem diskette'

if hibernation_available; then
  fail "hibernation is unavailable when only a longer state name contains disk"
fi
pass "hibernation is unavailable when only a longer state name contains disk"

rm "$sys_power/state"

if hibernation_available; then
  fail "hibernation is unavailable when the kernel has no sleep states at all"
fi
pass "hibernation is unavailable when the kernel has no sleep states at all"

# A kernel built without suspend offers hibernation and nothing else.
write_sleep_states 'disk'

hibernation_available || fail "hibernation is available when the kernel offers no other sleep state"
pass "hibernation is available when the kernel offers no other sleep state"

: >"$sys_power/image_size"

if hibernation_available; then
  fail "hibernation is unavailable when the hibernation image size does not read"
fi
pass "hibernation is unavailable when the hibernation image size does not read"

printf '%s\n' '6871947673' >"$sys_power/image_size"
write_sleep_states 'freeze mem disk'
write_swaps '/dev/zram0                              partition       8388604         0       100'

if hibernation_available; then
  fail "hibernation is unavailable when only zram swap is active"
fi
pass "hibernation is unavailable when only zram swap is active"

write_swaps '/swap/swapfile                          file            1024            0       0'

if hibernation_available; then
  fail "hibernation is unavailable when swap is smaller than the hibernation image"
fi
pass "hibernation is unavailable when swap is smaller than the hibernation image"

write_swaps '/swap/swapfile                          file            62914556        0       0'
rm "$resume_conf"

if hibernation_available; then
  fail "hibernation is unavailable without the resume config"
fi
pass "hibernation is unavailable without the resume config"
