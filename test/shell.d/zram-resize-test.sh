#!/bin/bash

source "$(dirname "${BASH_SOURCE[0]}")/base-test.sh"

require_command /usr/lib/systemd/system-generators/zram-generator

migration=$(grep -rl 'Resize zram to match the shipped config' "$ROOT/migrations" | head -n 1 || true)
[[ -n $migration ]] || fail "zram resize migration exists"

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

# The migration shells out to sudo, systemctl and omarchy-state. Stub all three
# so the test never touches the real system, and record what each run did.
stub_bin="$TMPDIR/bin"
mkdir -p "$stub_bin"

cat >"$stub_bin/sudo" <<'STUB'
#!/bin/bash
exec "$@"
STUB

cat >"$stub_bin/systemctl" <<'STUB'
#!/bin/bash
echo "systemctl $*" >>"$ACTIONS"
[[ ${SYSTEMCTL_FAIL:-0} == 1 ]] && exit 1
exit 0
STUB

cat >"$stub_bin/omarchy-state" <<'STUB'
#!/bin/bash
echo "omarchy-state $*" >>"$ACTIONS"
STUB

chmod +x "$stub_bin/sudo" "$stub_bin/systemctl" "$stub_bin/omarchy-state"

# ZRAM_GENERATOR_ROOT redirects both the config search and /proc/meminfo, so the
# migration's own generator call resolves against this fixture instead of the
# host. 16G of RAM against the shipped config is a 8192MB device.
gen_root="$TMPDIR/genroot"
mkdir -p "$gen_root/usr/lib/systemd/zram-generator.conf.d" "$gen_root/proc"
cp "$ROOT/default/systemd/zram-generator.conf.d/90-omarchy.conf" \
  "$gen_root/usr/lib/systemd/zram-generator.conf.d/"
printf 'MemTotal:       %d kB\n' $((16 * 1024 * 1024)) >"$gen_root/proc/meminfo"

desired_bytes=$((8192 * 1024 * 1024))

# omarchy-migrate runs each migration with `bash -euo pipefail` and stops the
# whole chain on a non-zero exit, so match that invocation exactly.
run_migration() {
  local disksize="$1" used="$2" fail_reload="${3:-0}"

  # A machine with no zram device has no /sys/block/zram0 at all, so an empty
  # size means the file is gone rather than blank; the migration tells those
  # two apart now.
  if [[ -n $disksize ]]; then
    printf '%s' "$disksize" >"$TMPDIR/disksize"
  else
    rm -f "$TMPDIR/disksize"
  fi

  printf 'Filename\tType\tSize\tUsed\tPriority\n' >"$TMPDIR/swaps"
  [[ -n $used ]] &&
    printf '/dev/zram0 partition 8388604 %s 100\n' "$used" >>"$TMPDIR/swaps"

  : >"$TMPDIR/actions"

  PATH="$stub_bin:$PATH" \
    ACTIONS="$TMPDIR/actions" \
    SYSTEMCTL_FAIL="$fail_reload" \
    ZRAM_GENERATOR_ROOT="$gen_root" \
    OMARCHY_ZRAM_DISKSIZE="$TMPDIR/disksize" \
    OMARCHY_SWAPS="$TMPDIR/swaps" \
    bash -euo pipefail "$migration" >/dev/null ||
    fail "migration exits clean (disksize=$disksize used=$used reload_fail=$fail_reload)"
}

did() { grep -qF "$1" "$TMPDIR/actions"; }

# Already the size the config asks for: the device is correct however it got
# there, so the migration must not restart it or ask for a reboot.
run_migration "$desired_bytes" 4193612
[[ -s $TMPDIR/actions ]] && fail "correctly sized device is left alone" \
  "expected no privileged calls, got: $(cat "$TMPDIR/actions")"
pass "correctly sized device is left alone"
pass "correctly sized device asks for no reboot"

# Right size but still in use, and the reload never even happens.
run_migration "$desired_bytes" 0
did "systemctl restart" && fail "correctly sized empty device is left alone"
pass "correctly sized empty device is left alone"

# Wrong size and empty: safe to resize now.
run_migration $((4096 * 1024 * 1024)) 0
did "systemctl restart dev-zram0.swap" || fail "empty device is restarted"
did "omarchy-state set reboot-required" && fail "empty device asks for no reboot"
pass "empty device is restarted"
pass "empty device asks for no reboot"

# Wrong size with pages stored: resizing would fault them all back in, so defer.
run_migration $((4096 * 1024 * 1024)) 4193612
did "systemctl restart" && fail "device in use is not restarted"
did "omarchy-state set reboot-required" || fail "device in use asks for a reboot"
pass "device in use is not restarted"
pass "device in use asks for a reboot"

# No zram device at all reads as empty, and the restart brings it up.
run_migration "" ""
did "systemctl restart dev-zram0.swap" || fail "absent device is created"
pass "absent device is created"

# A device that exists but is swapped off reads empty too, and there the
# restart resets it, which fails against whatever still holds it open. Nothing
# to gain over the reboot that would have resized it anyway.
run_migration $((4096 * 1024 * 1024)) ""
did "systemctl restart" && fail "swapped-off device is not restarted"
did "omarchy-state set reboot-required" || fail "swapped-off device asks for a reboot"
pass "swapped-off device is not restarted"
pass "swapped-off device asks for a reboot"

# A failed daemon-reload must fall back to asking for a reboot.
run_migration $((4096 * 1024 * 1024)) 0 1
did "systemctl restart" && fail "failed reload does not restart"
did "omarchy-state set reboot-required" || fail "failed reload asks for a reboot"
pass "failed reload does not restart"
pass "failed reload asks for a reboot"
