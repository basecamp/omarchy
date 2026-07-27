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

# updatedb dies on a config that defines a variable twice, so hand every
# rewritten file to the real parser rather than trusting the greps below.
empty_tree="$test_tmp/empty-tree"
mkdir -p "$empty_tree"

assert_conf_parses() {
  command -v updatedb >/dev/null || return 0

  local errors
  errors=$(updatedb --config-file "$1" -U "$empty_tree" -o "$test_tmp/plocate.db" 2>&1 >/dev/null | grep -F "$1:" || true)
  [[ -z $errors ]] || fail "updatedb accepts the rewritten config" "$errors"
}

conf="$test_tmp/updatedb.conf"
stock_conf "$conf"

OMARCHY_UPDATEDB_CONF_PATH="$conf" bash -euo pipefail "$config_script" >/dev/null

grep -qFx 'PRUNE_BIND_MOUNTS = "no"' "$conf" || fail "locate config indexes Btrfs subvolume mounts like /home"
grep -qF 'PRUNEPATHS = "/.snapshots /afs' "$conf" || fail "locate config prunes /.snapshots"
assert_conf_parses "$conf"
pass "locate config skips Btrfs snapshots and indexes Btrfs subvolumes"

OMARCHY_UPDATEDB_CONF_PATH="$conf" bash -euo pipefail "$config_script" >/dev/null

[[ $(grep -o '/\.snapshots' "$conf" | wc -l) -eq 1 ]] || fail "locate config is idempotent"
assert_conf_parses "$conf"
pass "locate config leaves an already-configured file alone"

OMARCHY_UPDATEDB_CONF_PATH="$test_tmp/missing.conf" bash -euo pipefail "$config_script" >/dev/null
pass "locate config tolerates a missing updatedb.conf"

# A hand-edited updatedb.conf may drop the settings entirely, or write them
# without the spaces around the "=" or the quotes that the stock Arch file uses.
conf="$test_tmp/sparse-updatedb.conf"
printf '%s\n' 'PRUNENAMES = ".git .hg .svn"' >"$conf"

OMARCHY_UPDATEDB_CONF_PATH="$conf" bash -euo pipefail "$config_script" >/dev/null

grep -qFx 'PRUNE_BIND_MOUNTS = "no"' "$conf" || fail "locate config adds a missing PRUNE_BIND_MOUNTS"
grep -qFx 'PRUNEPATHS = "/.snapshots"' "$conf" || fail "locate config adds a missing PRUNEPATHS"
assert_conf_parses "$conf"
pass "locate config adds settings a hand-edited updatedb.conf is missing"

conf="$test_tmp/unspaced-updatedb.conf"
printf '%s\n' 'PRUNE_BIND_MOUNTS="yes"' 'PRUNEPATHS="/tmp /var/tmp"' >"$conf"

OMARCHY_UPDATEDB_CONF_PATH="$conf" bash -euo pipefail "$config_script" >/dev/null

grep -qFx 'PRUNE_BIND_MOUNTS = "no"' "$conf" || fail "locate config rewrites an unspaced PRUNE_BIND_MOUNTS"
grep -qFx 'PRUNEPATHS = "/.snapshots /tmp /var/tmp"' "$conf" || fail "locate config prunes /.snapshots in an unspaced PRUNEPATHS"
[[ $(grep -c 'PRUNEPATHS' "$conf") -eq 1 ]] || fail "locate config keeps a single PRUNEPATHS setting"
assert_conf_parses "$conf"
pass "locate config handles updatedb.conf written without spaces around ="

# updatedb allows a comment after a value and indented settings, and defining
# either setting twice makes it refuse to run at all.
conf="$test_tmp/commented-updatedb.conf"
printf '%s\n' '  PRUNE_BIND_MOUNTS = "yes" # subvolumes look like bind mounts' \
  'PRUNEPATHS = "/tmp" # scratch' >"$conf"

OMARCHY_UPDATEDB_CONF_PATH="$conf" bash -euo pipefail "$config_script" >/dev/null

grep -qFx 'PRUNE_BIND_MOUNTS = "no"' "$conf" || fail "locate config rewrites an indented PRUNE_BIND_MOUNTS"
grep -qFx 'PRUNEPATHS = "/.snapshots /tmp"' "$conf" || fail "locate config keeps the paths a commented PRUNEPATHS already prunes"
[[ $(grep -c 'PRUNEPATHS' "$conf") -eq 1 ]] || fail "locate config replaces a commented PRUNEPATHS instead of adding a second one"
assert_conf_parses "$conf"
pass "locate config handles indented settings and trailing comments"

# A hand-edited file may have dropped the quotes updatedb requires, which
# leaves it unparseable until something writes the setting out properly.
conf="$test_tmp/unquoted-updatedb.conf"
printf '%s\n' 'PRUNEPATHS = /tmp' >"$conf"

OMARCHY_UPDATEDB_CONF_PATH="$conf" bash -euo pipefail "$config_script" >/dev/null

grep -qFx 'PRUNEPATHS = "/.snapshots"' "$conf" || fail "locate config repairs an unquoted PRUNEPATHS"
[[ $(grep -c 'PRUNEPATHS' "$conf") -eq 1 ]] || fail "locate config replaces an unquoted PRUNEPATHS instead of adding a second one"
assert_conf_parses "$conf"
pass "locate config handles updatedb.conf written without quotes"

# A path that merely ends in /.snapshots is not the root snapshot directory.
conf="$test_tmp/nested-snapshots-updatedb.conf"
printf '%s\n' 'PRUNEPATHS = "/var/lib/machines/.snapshots"' >"$conf"

OMARCHY_UPDATEDB_CONF_PATH="$conf" bash -euo pipefail "$config_script" >/dev/null

grep -qFx 'PRUNEPATHS = "/.snapshots /var/lib/machines/.snapshots"' "$conf" || fail "locate config prunes /.snapshots alongside a path that ends in it"
assert_conf_parses "$conf"
pass "locate config tells /.snapshots apart from a path that ends in it"

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
grep -qFx 'systemctl restart --no-block plocate-updatedb.service' "$test_tmp/calls.log" || fail "locate migration replaces an in-flight run and rebuilds the index without blocking"
pass "locate migration fixes existing installs and rebuilds the index"

: >"$test_tmp/calls.log"

TEST_LOG="$test_tmp/calls.log" \
PATH="$fake_bin:$PATH" \
OMARCHY_PATH="$ROOT" \
OMARCHY_UPDATEDB_CONF_PATH="$conf" \
  bash -euo pipefail "$locate_migration" >/dev/null

[[ ! -s $test_tmp/calls.log ]] || fail "locate migration skips already-configured installs"
pass "locate migration is a no-op once updatedb.conf is configured"

# A dev checkout carries migrations from a release whose install scripts the
# checked-out tree may not have yet, and omarchy-migrate runs under set -e.
: >"$test_tmp/calls.log"
conf="$test_tmp/no-config-script-updatedb.conf"
stock_conf "$conf"

TEST_LOG="$test_tmp/calls.log" \
PATH="$fake_bin:$PATH" \
OMARCHY_PATH="$test_tmp/empty" \
OMARCHY_UPDATEDB_CONF_PATH="$conf" \
  bash -euo pipefail "$locate_migration" >/dev/null ||
  fail "locate migration survives a tree without the locate config script"

[[ ! -s $test_tmp/calls.log ]] || fail "locate migration touches nothing without the locate config script"
pass "locate migration is a no-op when the locate config script is missing"
