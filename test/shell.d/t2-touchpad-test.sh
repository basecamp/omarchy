#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

leaf="$ROOT/install/hardware/apple/fix-t2-touchpad.sh"
all="$ROOT/install/hardware/all.sh"
migration="$ROOT/migrations/1786910195.sh"

grep -q 'apple/fix-t2-touchpad.sh' "$all" ||
  fail "the trackpad fix runs during hardware setup"

# The property line must keep its leading space: hwdb treats an unindented line
# as a new match, so losing it turns the property into a match that never fires
# and the file stops doing anything without failing.
grep -q '^ ID_INPUT_TOUCHPAD_INTEGRATION=internal$' "$leaf" ||
  fail "the hwdb property stays indented under its match"
pass "the trackpad fix is orchestrated and its hwdb entry is well formed"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

stub_bin="$test_tmp/bin"
calls="$test_tmp/calls.log"
hwdb="$test_tmp/etc/udev/hwdb.d/70-omarchy-t2-touchpad.hwdb"
mkdir -p "$stub_bin"
: >"$calls"

cat >"$stub_bin/lspci" <<'SH'
#!/bin/bash

# Chatty like real lspci: keep writing well past the pipe buffer after the
# match, so a grep -q consumer would kill this stub with SIGPIPE and pipefail
# would read that as "no T2 hardware" (#6608).
if (( ${T2_HARDWARE:-0} == 1 )); then
  echo '01:00.0 Bridge [0680]: Apple Inc. T2 Security Chip [106b:1801]'
fi
for _ in {1..4096}; do
  echo '02:00.0 Host bridge [0600]: Filler Device [ffff:0000]'
done
SH

cat >"$stub_bin/systemd-hwdb" <<'SH'
#!/bin/bash

printf 'systemd-hwdb' >>"$TEST_LOG"
printf '\t%s' "$@" >>"$TEST_LOG"
printf '\n' >>"$TEST_LOG"
SH

cat >"$stub_bin/sudo" <<'SH'
#!/bin/bash

"$@"
SH

# Stubbed rather than run: the real one would write the running user's state.
cat >"$stub_bin/omarchy-state" <<'SH'
#!/bin/bash

printf 'omarchy-state' >>"$TEST_LOG"
printf '\t%s' "$@" >>"$TEST_LOG"
printf '\n' >>"$TEST_LOG"
SH

chmod +x "$stub_bin"/*

# The leaf writes to an absolute path, so redirect it into the sandbox. pipefail
# is on, the context the SIGPIPE gate in #6608 was about.
run_leaf() {
  local t2="${1:-0}"
  rm -rf "$test_tmp/etc"
  : >"$calls"

  local script="$test_tmp/leaf.sh"
  sed -e "s|/etc/udev/hwdb.d|$test_tmp/etc/udev/hwdb.d|g" "$leaf" >"$script"

  T2_HARDWARE="$t2" PATH="$stub_bin:$PATH" TEST_LOG="$calls" \
    bash -eE -o pipefail -c 'source "$1"' bash "$script" </dev/null
}

run_leaf 1 >/dev/null
grep -q '^touchpad:usb:v05acp0340:\*$' "$hwdb" 2>/dev/null ||
  fail "a T2 Mac gets the trackpad hwdb entry" "$(ls -R "$test_tmp/etc" 2>&1)"
grep -Fq $'systemd-hwdb\tupdate' "$calls" ||
  fail "the hwdb text entry is compiled into the binary database" "$(cat "$calls")"
pass "a T2 Mac gets the trackpad hwdb entry"

run_leaf 0 >/dev/null
[[ ! -e $hwdb ]] || fail "non-T2 hardware is left alone" "$(cat "$hwdb")"
[[ ! -s $calls ]] || fail "non-T2 hardware compiles nothing" "$(cat "$calls")"
pass "non-T2 hardware is left alone"

# Installs that predate the fix never ran the leaf, so the migration has to
# reach them.
run_migration() {
  local t2="${1:-1}"
  : >"$calls"

  T2_HARDWARE="$t2" PATH="$stub_bin:$PATH" TEST_LOG="$calls" \
    OMARCHY_T2_TOUCHPAD_HWDB="$hwdb" \
    bash -euo pipefail "$migration" >/dev/null
}

rm -rf "$test_tmp/etc"
run_migration 1
grep -q '^ ID_INPUT_TOUCHPAD_INTEGRATION=internal$' "$hwdb" 2>/dev/null ||
  fail "the migration fixes a T2 install that never got the entry" "$(ls -R "$test_tmp/etc" 2>&1)"
# libinput only rebuilds the device on a udev add, which the running session
# will not see.
grep -Fq $'omarchy-state\tset\treboot-required' "$calls" ||
  fail "the migration asks for the session restart that applies it" "$(cat "$calls")"
pass "the migration fixes a T2 install that never got the entry"

run_migration 1
[[ ! -s $calls ]] || fail "a repaired install is left untouched" "$(cat "$calls")"
pass "the migration is machine-idempotent across users"

# A half-written file from an interrupted run is not a repaired install.
printf 'touchpad:usb:v05acp0340:*\n' >"$hwdb"
run_migration 1
grep -q '^ ID_INPUT_TOUCHPAD_INTEGRATION=internal$' "$hwdb" ||
  fail "a match with no property is rewritten" "$(cat "$hwdb")"
pass "a match with no property is rewritten"

rm -rf "$test_tmp/etc"
run_migration 0
[[ ! -e $hwdb ]] || fail "the migration skips unrelated hardware" "$(cat "$hwdb")"
[[ ! -s $calls ]] || fail "the migration escalates nothing on unrelated hardware" "$(cat "$calls")"
pass "the migration skips unrelated hardware"
