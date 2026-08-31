#!/bin/bash

set -euo pipefail

# The default keyring seed must not plant a plaintext Default_keyring.keyring
# stub. gnome-keyring 50.x rejects that format and creates empty throwaway
# keyrings on every login, wiping secrets.

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

home="$test_tmp/home"
mkdir -p "$home"

HOME="$home" bash -c 'source "$1"' bash "$ROOT/install/user/default-keyring.sh"

[[ -d $home/.local/share/keyrings ]] || fail "seed creates the keyrings directory"
[[ -f $home/.local/share/keyrings/default ]] || fail "seed writes the default pointer"
grep -qx 'Default_keyring' "$home/.local/share/keyrings/default" ||
  fail "default pointer names Default_keyring"

[[ ! -e $home/.local/share/keyrings/Default_keyring.keyring ]] ||
  fail "seed must not plant Default_keyring.keyring" "$(ls -la "$home/.local/share/keyrings")"

# Idempotent: second run leaves an existing native-looking file alone and does
# not recreate a stub.
printf 'native-bytes' >"$home/.local/share/keyrings/Default_keyring.keyring"
HOME="$home" bash -c 'source "$1"' bash "$ROOT/install/user/default-keyring.sh"
grep -qx 'native-bytes' "$home/.local/share/keyrings/Default_keyring.keyring" ||
  fail "seed must not overwrite an existing keyring file"

pass "default-keyring seed only writes directory + default pointer"

# Migration quarantines plaintext stubs and preserves real keyring files.
mig_home="$test_tmp/mig-home"
mkdir -p "$mig_home/.local/share/keyrings"
stub="$mig_home/.local/share/keyrings/Default_keyring.keyring"
cat >"$stub" <<'EOF'
[keyring]
display-name=Default keyring
ctime=1700000000
mtime=0
lock-on-idle=false
lock-after=false
EOF
# A binary-ish file that is not a stub must stay.
printf 'GnomeKeyring\0fake' >"$mig_home/.local/share/keyrings/Default_keyring_1.keyring"

HOME="$mig_home" bash -euo pipefail "$ROOT/migrations/1788139500.sh" \
  >"$test_tmp/mig.out" 2>"$test_tmp/mig.err" ||
  fail "migration must succeed" "$(cat "$test_tmp/mig.err"; cat "$test_tmp/mig.out")"

[[ ! -e $stub ]] || fail "migration removes the plaintext stub from the live path"
[[ -f $mig_home/.local/share/keyrings/omarchy-invalid-stub-backup/Default_keyring.keyring ]] ||
  fail "migration quarantines the stub instead of deleting it"
[[ -f $mig_home/.local/share/keyrings/Default_keyring_1.keyring ]] ||
  fail "migration must not touch non-stub keyring files"
grep -qx 'Default_keyring' "$mig_home/.local/share/keyrings/default" ||
  fail "migration ensures the default pointer exists"

# Second run is a no-op.
HOME="$mig_home" bash -euo pipefail "$ROOT/migrations/1788139500.sh" \
  >"$test_tmp/mig2.out" 2>"$test_tmp/mig2.err" ||
  fail "migration must be idempotent"
[[ -f $mig_home/.local/share/keyrings/Default_keyring_1.keyring ]] ||
  fail "idempotent migration still leaves native files alone"

pass "migration quarantines plaintext keyring stubs only"

# upgrade-to-quattro must not reintroduce the stub pattern.
if grep -n 'display-name=Default keyring' "$ROOT/bin/omarchy-upgrade-to-quattro" >/dev/null; then
  fail "upgrade-to-quattro must not write the plaintext keyring stub"
fi
if ! grep -n 'keyring_dir=' "$ROOT/bin/omarchy-upgrade-to-quattro" >/dev/null; then
  fail "upgrade-to-quattro should still seed the keyrings directory"
fi

pass "upgrade-to-quattro no longer plants the plaintext keyring stub"
