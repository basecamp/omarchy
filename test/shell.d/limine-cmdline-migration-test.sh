#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

migration="$ROOT/migrations/1786482992.sh"
packaged_defaults="$ROOT/etc/limine-entry-tool.d/omarchy-defaults.conf"

grep -Fq 'KERNEL_CMDLINE[default]+=" initramfs_async=0"' "$packaged_defaults" ||
  fail "the packaged Limine defaults still unpack the initramfs synchronously"
pass "packaged Limine defaults keep Plymouth alive at the LUKS prompt"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

stub_bin="$test_tmp/bin"
calls="$test_tmp/calls.log"
mkdir -p "$stub_bin"
: >"$calls"

cat >"$stub_bin/omarchy-cmd-present" <<'SH'
#!/bin/bash

(( ${LIMINE_MKINITCPIO_INSTALLED:-1} == 1 ))
SH

cat >"$stub_bin/sudo" <<'SH'
#!/bin/bash

printf 'sudo' >>"$TEST_LOG"
printf '\t%s' "$@" >>"$TEST_LOG"
printf '\n' >>"$TEST_LOG"
"$@"
SH

cat >"$stub_bin/limine-mkinitcpio" <<'SH'
#!/bin/bash

echo 'limine-mkinitcpio' >>"$TEST_LOG"
SH

chmod +x "$stub_bin"/*

defaults_conf="$test_tmp/omarchy-defaults.conf"
running_cmdline="$test_tmp/cmdline"
rebuild_marker="$test_tmp/rebuild-complete"

cp "$packaged_defaults" "$defaults_conf"

# A boot image baked before quattro's defaults landed: the pre-quattro command
# line plus the machine's own root parameters, and none of the new ones.
stale_cmdline='quiet splash cryptdevice=PARTUUID=fake:root root=/dev/mapper/root rw'

# Everything the packaged defaults ask for, as a rebuilt image would carry it.
configured=$(sed -n 's/^KERNEL_CMDLINE\[default\]+="\(.*\)"[[:space:]]*$/\1/p' "$defaults_conf" | tr '\n' ' ')
current_cmdline="cryptdevice=PARTUUID=fake:root root=/dev/mapper/root rw $configured"

run_migration() {
  PATH="$stub_bin:$PATH" \
    TEST_LOG="$calls" \
    OMARCHY_LIMINE_DEFAULTS_CONF="$defaults_conf" \
    OMARCHY_RUNNING_CMDLINE="$running_cmdline" \
    OMARCHY_LIMINE_REBUILD_MARKER="$rebuild_marker" \
    bash -euo pipefail "$migration" >/dev/null
}

echo "$stale_cmdline" >"$running_cmdline"
run_migration

grep -Fxq 'limine-mkinitcpio' "$calls" ||
  fail "a boot image older than the Limine defaults is rebuilt"
[[ -f $rebuild_marker ]] || fail "the rebuild records the machine-wide repair"
pass "migration rebuilds a boot image that predates the Limine defaults"

: >"$calls"
run_migration

[[ ! -s $calls ]] || fail "a recorded rebuild is not repeated" "$(cat "$calls")"
pass "migration is machine-idempotent before reboot"

rm -f "$rebuild_marker"
: >"$calls"
run_migration

grep -Fxq 'limine-mkinitcpio' "$calls" ||
  fail "an interrupted rebuild is retried"
[[ -f $rebuild_marker ]] || fail "a retried rebuild records completion"
pass "migration retries an interrupted rebuild"

echo "$current_cmdline" >"$running_cmdline"
rm -f "$rebuild_marker"
: >"$calls"
run_migration

[[ ! -s $calls ]] || fail "a boot image matching the defaults is left alone" "$(cat "$calls")"
[[ ! -e $rebuild_marker ]] || fail "an untouched machine is not marked as repaired"
pass "migration skips a boot image that already carries the defaults"

echo "$stale_cmdline" >"$running_cmdline"
: >"$calls"
LIMINE_MKINITCPIO_INSTALLED=0 run_migration

[[ ! -s $calls ]] || fail "installs without limine-mkinitcpio are skipped" "$(cat "$calls")"

mv "$defaults_conf" "$defaults_conf.away"
run_migration
mv "$defaults_conf.away" "$defaults_conf"

[[ ! -s $calls ]] || fail "installs without the Limine defaults are skipped" "$(cat "$calls")"
pass "migration skips installs it does not apply to"
