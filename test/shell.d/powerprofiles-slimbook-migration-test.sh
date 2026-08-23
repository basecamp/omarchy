#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/base-test.sh"

# Root can write the attribute whatever its mode is, so the handover this
# migration performs cannot be observed from a root test run.
if (( EUID == 0 )); then
  pass "running as root; skipping the qc71 attribute handover"
  exit 0
fi

migration="$ROOT/migrations/1787422694.sh"
test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT

mkdir -p "$test_dir/bin"

# sudo runs the real command, so the rule below is copied into the test tree and
# the elevated udev calls land in the stub beside it.
cat >"$test_dir/bin/sudo" <<'STUB'
#!/bin/bash

printf 'sudo %s\n' "$*" >>"$CALLS"
exec "$@"
STUB

# `udevadm trigger` only queues the event: the rule's chgrp and chmod are still
# pending when it returns, and only --settle waits for them. Granting access
# just for --settle is what keeps this test honest about that difference. A
# Slimbook hands the attribute to the wheel group; here the test user owns the
# stand-in file, so the owner bit stands in for that membership.
cat >"$test_dir/bin/udevadm" <<'STUB'
#!/bin/bash

printf 'udevadm %s\n' "$*" >>"$CALLS"

if [[ $1 == "trigger" && " $* " == *" --settle "* ]]; then
  chmod u+w "$OMARCHY_QC71_PERFORMANCE_MODE"
fi
STUB

cat >"$test_dir/bin/powerprofilesctl" <<'STUB'
#!/bin/bash

[[ $1 == "get" ]] && echo "performance"
STUB

chmod +x "$test_dir/bin/"*

export CALLS="$test_dir/calls"
export OMARCHY_PATH="$ROOT"
export OMARCHY_DMI_SYS_VENDOR="$test_dir/sys_vendor"
export OMARCHY_QC71_PERFORMANCE_MODE="$test_dir/performance_mode"
export OMARCHY_QC71_UDEV_RULE="$test_dir/udev/99-omarchy-slimbook-qc71-performance-mode.rules"

source_rule="$ROOT/default/udev/slimbook-qc71-performance-mode.rules"

# A Slimbook that has never had the rule: root owns the mode, so the desktop
# cannot write it and the bar and the fan disagree.
reset_machine() {
  rm -rf "$test_dir/udev"
  printf 'SLIMBOOK\n' >"$OMARCHY_DMI_SYS_VENDOR"
  printf '2\n' >"$OMARCHY_QC71_PERFORMANCE_MODE"
  chmod 0444 "$OMARCHY_QC71_PERFORMANCE_MODE"
}

run_migration() {
  : >"$CALLS"

  PATH="$test_dir/bin:$ROOT/bin:$PATH" \
    bash -euo pipefail "$migration" >/dev/null 2>"$test_dir/stderr"
}

reset_machine
run_migration

cmp -s "$source_rule" "$OMARCHY_QC71_UDEV_RULE" ||
  fail "migration installs the udev rule" "$(cat "$CALLS")"
pass "migration installs the udev rule"

grep -q 'udevadm trigger .*--settle' "$CALLS" ||
  fail "migration waits for the rule to be applied" "$(cat "$CALLS")"
pass "migration waits for the rule to be applied"

# A bare trigger on the platform device also reaches the qc71 input device
# underneath, and slimbook-service reads any non-add action there as the driver
# going away: it then stops mirroring the profile onto the fan and TDP modes for
# the rest of the session, leaving this migration to break what it came to fix.
grep -q 'udevadm trigger .*--subsystem-match=platform' "$CALLS" ||
  fail "migration keeps the trigger off the qc71 input device" "$(cat "$CALLS")"
pass "migration keeps the trigger off the qc71 input device"

# The whole point of the migration: the machine matches the bar afterwards,
# rather than waiting for the next profile change.
[[ $(<"$OMARCHY_QC71_PERFORMANCE_MODE") == "3" ]] ||
  fail "migration carries the current profile onto the hardware" "$(cat "$CALLS")"
pass "migration carries the current profile onto the hardware"

[[ ! -s $test_dir/stderr ]] ||
  fail "migration completes without a warning" "$(cat "$test_dir/stderr")"
pass "migration completes without a warning"

# A second user on the same laptop finds the rule installed and the attribute
# already handed over, so there is nothing left to do.
run_migration

[[ ! -s $CALLS ]] ||
  fail "migration touches nothing on a second run" "$(cat "$CALLS")"
pass "migration touches nothing on a second run"

# The rule can be in place while the bound driver never saw it, from a hand
# install or an interrupted run. The attribute is what decides, not the file.
chmod 0444 "$OMARCHY_QC71_PERFORMANCE_MODE"
run_migration

grep -q 'udevadm trigger .*--settle' "$CALLS" ||
  fail "migration applies a rule the bound driver never saw" "$(cat "$CALLS")"
[[ $(<"$OMARCHY_QC71_PERFORMANCE_MODE") == "3" ]] ||
  fail "migration syncs after applying an unapplied rule" "$(cat "$CALLS")"
pass "migration applies a rule the bound driver never saw"

# Slimbook ships the driver from its own repository, so a fresh install mostly
# gets it later, and a fresh install marks every migration done. The rule has to
# be laid down now, for the module to find when it binds, and nothing may touch
# a driver that is not there.
reset_machine
rm -f "$OMARCHY_QC71_PERFORMANCE_MODE"
run_migration

cmp -s "$source_rule" "$OMARCHY_QC71_UDEV_RULE" ||
  fail "migration installs the rule before the driver is there" "$(cat "$CALLS")"
if grep -q 'udevadm trigger' "$CALLS"; then
  fail "migration leaves a missing driver alone" "$(cat "$CALLS")"
fi
[[ ! -s $test_dir/stderr ]] ||
  fail "migration stays quiet without the driver" "$(cat "$test_dir/stderr")"
pass "migration installs the rule before the driver is there"

# Every other machine has to come out of this untouched.
reset_machine
printf 'LENOVO\n' >"$OMARCHY_DMI_SYS_VENDOR"
run_migration

if [[ -e $OMARCHY_QC71_UDEV_RULE ]]; then
  fail "migration leaves other vendors alone"
fi
[[ ! -s $CALLS ]] || fail "migration leaves other vendors alone" "$(cat "$CALLS")"
pass "migration leaves other vendors alone"
