#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

leaf="$ROOT/install/hardware/apple/fix-brcmfmac-suspend.sh"
hook_source="$ROOT/default/systemd/system-sleep/t2-wifi-suspend"
all="$ROOT/install/hardware/all.sh"
migration="$ROOT/migrations/1787605234.sh"

grep -q 'apple/fix-brcmfmac-suspend.sh' "$all" ||
  fail "the Wi-Fi suspend fix runs during hardware setup"
pass "the Wi-Fi suspend fix runs during hardware setup"

[[ -x $hook_source ]] || fail "the sleep hook ships executable, or systemd-sleep silently skips it"
pass "the sleep hook ships executable"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

stub_bin="$test_tmp/bin"
calls="$test_tmp/calls.log"
dest="$test_tmp/usr/lib/systemd/system-sleep/t2-wifi-suspend"
mkdir -p "$stub_bin"

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

cat >"$stub_bin/sudo" <<'SH'
#!/bin/bash

printf 'sudo' >>"$TEST_LOG"
printf '\t%s' "$@" >>"$TEST_LOG"
printf '\n' >>"$TEST_LOG"
"$@"
SH

chmod +x "$stub_bin"/*

run_leaf() {
  local t2="$1"
  rm -rf "$test_tmp/usr"

  local script="$test_tmp/leaf.sh"
  sed "s|/usr/lib/systemd/system-sleep|$test_tmp/usr/lib/systemd/system-sleep|g" \
    "$leaf" >"$script"

  T2_HARDWARE="$t2" OMARCHY_PATH="$ROOT" PATH="$stub_bin:$PATH" \
    bash -eE -o pipefail -c 'source "$1"' bash "$script" </dev/null
}

run_leaf 1 >/dev/null
cmp -s "$hook_source" "$dest" ||
  fail "a T2 Mac gets the Wi-Fi suspend hook" "$(ls -R "$test_tmp/usr" 2>&1)"
pass "a T2 Mac gets the Wi-Fi suspend hook"

run_leaf 0 >/dev/null
[[ ! -e $dest ]] || fail "a non-T2 machine is left alone"
pass "a non-T2 machine is left alone"

# Installs that predate the fix never ran the leaf, so the migration has to
# reach them. It runs as the user under pipefail, the context #6608 was about.
run_migration() {
  local t2="$1"
  : >"$calls"

  T2_HARDWARE="$t2" PATH="$stub_bin:$PATH" TEST_LOG="$calls" \
    OMARCHY_PATH="$ROOT" \
    OMARCHY_T2_WIFI_SUSPEND_HOOK="$dest" \
    OMARCHY_T2_WIFI_SUSPEND_SOURCE="$hook_source" \
    bash -euo pipefail "$migration" >/dev/null
}

rm -rf "$test_tmp/usr"
run_migration 1
cmp -s "$hook_source" "$dest" ||
  fail "the migration fixes a T2 install that never got the hook" "$(ls -R "$test_tmp/usr" 2>&1)"
grep -Fq $'sudo\tcp\t-p' "$calls" ||
  fail "the migration escalates to install the hook" "$(cat "$calls")"
pass "the migration fixes a T2 install that never got the hook"

run_migration 1
[[ ! -s $calls ]] || fail "an already repaired T2 install is left untouched" "$(cat "$calls")"
pass "the migration is idempotent"

rm -rf "$test_tmp/usr"
run_migration 0
[[ ! -e $dest ]] || fail "the migration skips a machine without a T2"
[[ ! -s $calls ]] || fail "the migration escalates nothing on non-T2 machines" "$(cat "$calls")"
pass "the migration skips hardware without a T2"
