#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

config_script="$ROOT/install/config/locate.sh"
locate_migration="$ROOT/migrations/1784809451.sh"
[[ -f $locate_migration ]] || fail "locate migration exists"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

config_path_count=$(grep -cFx 'UPDATEDB_CONF_PATH=/etc/updatedb.conf' "$config_script" || true)
migration_path_count=$(grep -cFx 'UPDATEDB_CONF_PATH=/etc/updatedb.conf' "$locate_migration" || true)
config_path_assignments=$(grep -cE '^[[:space:]]*UPDATEDB_CONF_PATH=' "$config_script" || true)
migration_path_assignments=$(grep -cE '^[[:space:]]*UPDATEDB_CONF_PATH=' "$locate_migration" || true)
(( config_path_count == 1 && config_path_assignments == 1 )) || fail "locate config always selects the system updatedb.conf"
(( migration_path_count == 1 && migration_path_assignments == 1 )) || fail "locate migration always checks the system updatedb.conf"
if grep -qF 'OMARCHY_UPDATEDB_CONF_PATH' "$config_script" "$locate_migration"; then
  fail "locate scripts expose no environment-controlled config path"
fi
pass "locate scripts keep the privileged config path fixed"

run_config() {
  local config_path=$1

  sed "s|^UPDATEDB_CONF_PATH=/etc/updatedb.conf$|UPDATEDB_CONF_PATH=$config_path|" "$config_script" |
    bash -euo pipefail
}

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
  if ! errors=$(updatedb --config-file "$1" --require-visibility no -U "$empty_tree" -o "$test_tmp/plocate.db" 2>&1 >/dev/null); then
    fail "updatedb accepts the rewritten config" "$errors"
  fi
}

conf="$test_tmp/updatedb.conf"
stock_conf "$conf"

run_config "$conf" >/dev/null

grep -qFx 'PRUNE_BIND_MOUNTS = "no"' "$conf" || fail "locate config indexes Btrfs subvolume mounts like /home"
grep -qF 'PRUNEPATHS = "/.snapshots /afs' "$conf" || fail "locate config prunes /.snapshots"
assert_conf_parses "$conf"
pass "locate config skips Btrfs snapshots and indexes Btrfs subvolumes"

run_config "$conf" >/dev/null

[[ $(grep -o '/\.snapshots' "$conf" | wc -l) -eq 1 ]] || fail "locate config is idempotent"
assert_conf_parses "$conf"
pass "locate config leaves an already-configured file alone"

run_config "$test_tmp/missing.conf" >/dev/null
pass "locate config tolerates a missing updatedb.conf"

# A hand-edited updatedb.conf may drop the settings entirely, or write them
# without the spaces around the "=" or the quotes that the stock Arch file uses.
conf="$test_tmp/sparse-updatedb.conf"
printf '%s\n' 'PRUNENAMES = ".git .hg .svn"' >"$conf"

run_config "$conf" >/dev/null

grep -qFx 'PRUNE_BIND_MOUNTS = "no"' "$conf" || fail "locate config adds a missing PRUNE_BIND_MOUNTS"
grep -qFx 'PRUNEPATHS = "/.snapshots"' "$conf" || fail "locate config adds a missing PRUNEPATHS"
assert_conf_parses "$conf"
pass "locate config adds settings a hand-edited updatedb.conf is missing"

conf="$test_tmp/unspaced-updatedb.conf"
printf '%s\n' 'PRUNE_BIND_MOUNTS="yes"' 'PRUNEPATHS="/tmp /var/tmp"' >"$conf"

run_config "$conf" >/dev/null

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

run_config "$conf" >/dev/null

grep -qFx 'PRUNE_BIND_MOUNTS = "no"' "$conf" || fail "locate config rewrites an indented PRUNE_BIND_MOUNTS"
grep -qFx 'PRUNEPATHS = "/.snapshots /tmp"' "$conf" || fail "locate config keeps the paths a commented PRUNEPATHS already prunes"
[[ $(grep -c 'PRUNEPATHS' "$conf") -eq 1 ]] || fail "locate config replaces a commented PRUNEPATHS instead of adding a second one"
assert_conf_parses "$conf"
pass "locate config handles indented settings and trailing comments"

# A hand-edited file may have dropped the quotes updatedb requires, which
# leaves it unparseable until something writes the setting out properly.
conf="$test_tmp/unquoted-updatedb.conf"
printf '%s\n' 'PRUNEPATHS = /tmp' >"$conf"

run_config "$conf" >/dev/null

grep -qFx 'PRUNEPATHS = "/.snapshots"' "$conf" || fail "locate config repairs an unquoted PRUNEPATHS"
[[ $(grep -c 'PRUNEPATHS' "$conf") -eq 1 ]] || fail "locate config replaces an unquoted PRUNEPATHS instead of adding a second one"
assert_conf_parses "$conf"
pass "locate config handles updatedb.conf written without quotes"

# A path that merely ends in /.snapshots is not the root snapshot directory.
conf="$test_tmp/nested-snapshots-updatedb.conf"
printf '%s\n' 'PRUNEPATHS = "/var/lib/machines/.snapshots"' >"$conf"

run_config "$conf" >/dev/null

grep -qFx 'PRUNEPATHS = "/.snapshots /var/lib/machines/.snapshots"' "$conf" || fail "locate config prunes /.snapshots alongside a path that ends in it"
assert_conf_parses "$conf"
pass "locate config tells /.snapshots apart from a path that ends in it"

fake_bin="$test_tmp/bin"
mkdir -p "$fake_bin"

# PRUNEPATHS is untrusted config data. In particular, GNU sed replacement
# escapes and delimiters must never turn the reporter's harmless id marker
# into another sed command.
conf="$test_tmp/injection-updatedb.conf"
proof="$test_tmp/reporter-proof.txt"
rce_payload="\\x22;id > $proof;:|ew "
printf 'PRUNEPATHS = "%s"\n' "$rce_payload" >"$conf"

PATH="$fake_bin:$PATH" run_config "$conf" >/dev/null

[[ ! -e $proof ]] || fail "locate config keeps PRUNEPATHS data out of the sed program"
grep -qFx "PRUNEPATHS = \"/.snapshots $rce_payload\"" "$conf" || fail "locate config preserves a sed-like PRUNEPATHS value as data"
assert_conf_parses "$conf"
pass "locate config cannot execute commands embedded in PRUNEPATHS"

conf="$test_tmp/metachar-updatedb.conf"
metachar_paths='/tmp/amp&ersand /tmp/pipe|name /tmp/back\slash'
printf 'PRUNEPATHS = "%s"\n' "$metachar_paths" >"$conf"
chmod 0640 "$conf"
metadata_before=$(stat -c '%a %u:%g' "$conf")

run_config "$conf" >/dev/null

grep -qFx "PRUNEPATHS = \"/.snapshots $metachar_paths\"" "$conf" || fail "locate config preserves replacement metacharacters"
[[ $(stat -c '%a %u:%g' "$conf") == $metadata_before ]] || fail "locate config preserves updatedb.conf ownership and mode"
assert_conf_parses "$conf"
checksum_before=$(sha256sum "$conf")
run_config "$conf" >/dev/null
[[ $(sha256sum "$conf") == $checksum_before ]] || fail "locate config is byte-idempotent with metacharacters"
pass "locate config safely preserves metacharacters and file metadata"

cat >"$fake_bin/sudo" <<'STUB'
#!/bin/bash
{
  printf 'sudo'
  printf ' %s' "$@"
  printf '\n'
} >>"$TEST_LOG"
exec "$@"
STUB
chmod +x "$fake_bin/sudo"

cat >"$fake_bin/systemctl" <<'STUB'
#!/bin/bash
printf 'systemctl %s\n' "$*" >>"$TEST_LOG"
STUB
chmod +x "$fake_bin/systemctl"

trusted_conf="$test_tmp/migration-updatedb.conf"
poison_conf="$test_tmp/poison-updatedb.conf"
migration_trusted_proof="$test_tmp/migration-trusted-proof.txt"
migration_poison_proof="$test_tmp/migration-poison-proof.txt"
migration_trusted_payload="\\x22;id > $migration_trusted_proof;:|ew "
migration_poison_payload="\\x22;id > $migration_poison_proof;:|ew "
printf 'PRUNEPATHS = "%s"\n' "$migration_trusted_payload" >"$trusted_conf"
printf 'PRUNEPATHS = "%s"\n' "$migration_poison_payload" >"$poison_conf"
poison_checksum=$(sha256sum "$poison_conf")

migration_root="$test_tmp/migration-root"
mkdir -p "$migration_root/install/config"
staged_config_script="$migration_root/install/config/locate.sh"
staged_migration="$test_tmp/locate-migration.sh"
sed "s|^UPDATEDB_CONF_PATH=/etc/updatedb.conf$|UPDATEDB_CONF_PATH=$trusted_conf|" "$config_script" >"$staged_config_script"
sed "s|^UPDATEDB_CONF_PATH=/etc/updatedb.conf$|UPDATEDB_CONF_PATH=$trusted_conf|" "$locate_migration" >"$staged_migration"

TEST_LOG="$test_tmp/calls.log" \
PATH="$fake_bin:$PATH" \
OMARCHY_PATH="$migration_root" \
OMARCHY_UPDATEDB_CONF_PATH="$poison_conf" \
  bash -euo pipefail "$staged_migration" >/dev/null

grep -qFx 'PRUNE_BIND_MOUNTS = "no"' "$trusted_conf" || fail "locate migration rewrites updatedb.conf"
grep -qFx "PRUNEPATHS = \"/.snapshots $migration_trusted_payload\"" "$trusted_conf" || fail "locate migration prunes /.snapshots without compiling config data"
[[ ! -e $migration_trusted_proof && ! -e $migration_poison_proof ]] || fail "locate migration cannot execute the reporter payload"
[[ $(sha256sum "$poison_conf") == $poison_checksum ]] || fail "locate migration ignores an environment-selected config"
assert_conf_parses "$trusted_conf"
if grep -qF 'OMARCHY_UPDATEDB_CONF_PATH' "$test_tmp/calls.log" || grep -qF "$poison_conf" "$test_tmp/calls.log"; then
  fail "locate migration does not forward the untrusted config path through sudo"
fi
grep -qFx 'systemctl restart --no-block plocate-updatedb.service' "$test_tmp/calls.log" || fail "locate migration replaces an in-flight run and rebuilds the index without blocking"
pass "locate migration fixes existing installs and rebuilds the index"

: >"$test_tmp/calls.log"

TEST_LOG="$test_tmp/calls.log" \
PATH="$fake_bin:$PATH" \
OMARCHY_PATH="$migration_root" \
OMARCHY_UPDATEDB_CONF_PATH="$poison_conf" \
  bash -euo pipefail "$staged_migration" >/dev/null

[[ ! -s $test_tmp/calls.log ]] || fail "locate migration skips already-configured installs"
pass "locate migration is a no-op once updatedb.conf is configured"

# A dev checkout carries migrations from a release whose install scripts the
# checked-out tree may not have yet, and omarchy-migrate runs under set -e.
: >"$test_tmp/calls.log"
stock_conf "$trusted_conf"

TEST_LOG="$test_tmp/calls.log" \
PATH="$fake_bin:$PATH" \
OMARCHY_PATH="$test_tmp/empty" \
  bash -euo pipefail "$staged_migration" >/dev/null ||
  fail "locate migration survives a tree without the locate config script"

[[ ! -s $test_tmp/calls.log ]] || fail "locate migration touches nothing without the locate config script"
pass "locate migration is a no-op when the locate config script is missing"
