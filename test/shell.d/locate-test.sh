#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

config_script="$ROOT/install/config/locate.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

stock_conf() {
  cat >"$1" <<'CONF'
PRUNE_BIND_MOUNTS = "yes"
PRUNEFS = "9p afs autofs cifs fuse nfs nfs4 proc sysfs tmpfs"
PRUNENAMES = ".git .hg .svn"
PRUNEPATHS = "/afs /media /mnt /net /sfs /tmp /udev /var/cache /var/lib/pacman/local /var/lock /var/run /var/spool /var/tmp"
CONF
}

conf="$test_tmp/updatedb.conf"
stock_conf "$conf"

OMARCHY_UPDATEDB_CONF_PATH="$conf" bash -euo pipefail "$config_script" >/dev/null

grep -qFx 'PRUNE_BIND_MOUNTS = "no"' "$conf" || fail "locate config indexes Btrfs subvolume mounts like /home"
grep -qF 'PRUNEPATHS = "/.snapshots /afs' "$conf" || fail "locate config prunes /.snapshots"
pass "locate config skips Btrfs snapshots and indexes Btrfs subvolumes"

OMARCHY_UPDATEDB_CONF_PATH="$conf" bash -euo pipefail "$config_script" >/dev/null

[[ $(grep -o '/\.snapshots' "$conf" | wc -l) -eq 1 ]] || fail "locate config is idempotent"
pass "locate config leaves an already-configured file alone"

OMARCHY_UPDATEDB_CONF_PATH="$test_tmp/missing.conf" bash -euo pipefail "$config_script" >/dev/null
pass "locate config tolerates a missing updatedb.conf"

# A hand-edited updatedb.conf may drop the settings entirely, or write them
# without the spaces around the "=" that the stock Arch file uses.
conf="$test_tmp/sparse-updatedb.conf"
printf '%s\n' 'PRUNENAMES = ".git .hg .svn"' >"$conf"

OMARCHY_UPDATEDB_CONF_PATH="$conf" bash -euo pipefail "$config_script" >/dev/null

grep -qFx 'PRUNE_BIND_MOUNTS = "no"' "$conf" || fail "locate config adds a missing PRUNE_BIND_MOUNTS"
grep -qFx 'PRUNEPATHS = "/.snapshots"' "$conf" || fail "locate config adds a missing PRUNEPATHS"
pass "locate config adds settings a hand-edited updatedb.conf is missing"

conf="$test_tmp/unspaced-updatedb.conf"
printf '%s\n' 'PRUNE_BIND_MOUNTS="yes"' 'PRUNEPATHS="/tmp /var/tmp"' >"$conf"

OMARCHY_UPDATEDB_CONF_PATH="$conf" bash -euo pipefail "$config_script" >/dev/null

grep -qFx 'PRUNE_BIND_MOUNTS = "no"' "$conf" || fail "locate config rewrites an unspaced PRUNE_BIND_MOUNTS"
grep -qFx 'PRUNEPATHS="/.snapshots /tmp /var/tmp"' "$conf" || fail "locate config prunes /.snapshots in an unspaced PRUNEPATHS"
[[ $(grep -c '^PRUNEPATHS' "$conf") -eq 1 ]] || fail "locate config keeps a single PRUNEPATHS setting"
pass "locate config handles updatedb.conf written without spaces around ="

locate_migration=$(grep -rl 'Configure locate to skip Btrfs snapshots' "$ROOT/migrations" | head -n 1 || true)
[[ -n $locate_migration ]] || fail "locate migration exists"

fake_bin="$test_tmp/bin"
mkdir -p "$fake_bin"

cat >"$fake_bin/sudo" <<'STUB'
#!/bin/bash
exec "$@"
STUB
chmod +x "$fake_bin/sudo"

cat >"$fake_bin/systemctl" <<'STUB'
#!/bin/bash
printf 'systemctl %s\n' "$*" >>"$TEST_LOG"
STUB
chmod +x "$fake_bin/systemctl"

conf="$test_tmp/migration-updatedb.conf"
stock_conf "$conf"

TEST_LOG="$test_tmp/calls.log" \
PATH="$fake_bin:$PATH" \
OMARCHY_PATH="$ROOT" \
OMARCHY_UPDATEDB_CONF_PATH="$conf" \
  bash -euo pipefail "$locate_migration" >/dev/null

grep -qFx 'PRUNE_BIND_MOUNTS = "no"' "$conf" || fail "locate migration rewrites updatedb.conf"
grep -qF 'PRUNEPATHS = "/.snapshots /afs' "$conf" || fail "locate migration prunes /.snapshots"
grep -qFx 'systemctl start --no-block plocate-updatedb.service' "$test_tmp/calls.log" || fail "locate migration rebuilds the locate index without blocking"
pass "locate migration fixes existing installs and rebuilds the index"

: >"$test_tmp/calls.log"

TEST_LOG="$test_tmp/calls.log" \
PATH="$fake_bin:$PATH" \
OMARCHY_PATH="$ROOT" \
OMARCHY_UPDATEDB_CONF_PATH="$conf" \
  bash -euo pipefail "$locate_migration" >/dev/null

[[ ! -s $test_tmp/calls.log ]] || fail "locate migration skips already-configured installs"
pass "locate migration is a no-op once updatedb.conf is configured"
