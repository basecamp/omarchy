#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

# omarchy-update-available must exit 2 when checkupdates fails (#9798).
script="$ROOT/bin/omarchy-update-available"
[[ -f $script ]] || fail "omarchy-update-available is present"

# Source-level: checkupdates failure must propagate as exit 2.
grep -F 'checkupdates_exit' "$script" >/dev/null ||
  fail "omarchy-update-available captures checkupdates exit code"
grep -F 'exit 2' "$script" >/dev/null ||
  fail "omarchy-update-available exits 2 on checkupdates failure"
pass "omarchy-update-available exits 2 on checkupdates failure"

# SystemUpdate widget must preserve state on exit 2 (#9798).
widget="$ROOT/shell/plugins/bar/widgets/SystemUpdate.qml"
[[ -f $widget ]] || fail "SystemUpdate widget is present"

grep -E 'exitCode === 0' "$widget" >/dev/null ||
  fail "widget shows update icon on exit 0"
grep -E 'exitCode === 1' "$widget" >/dev/null ||
  fail "widget hides update icon on exit 1"
grep -F 'keep root.updateAvailable as-is' "$widget" >/dev/null ||
  fail "widget preserves state on check failure"
pass "widget preserves state on exit 0/1 and leaves failure unchanged"

# Functional test with stubbed checkupdates.
test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT
stub_bin="$test_tmp/bin"
mkdir -p "$stub_bin"

cat >"$stub_bin/checkupdates" <<'SH'
#!/bin/bash
case "${TEST_CHECKUPDATES_MODE:-error}" in
  error)  echo "checkupdates: failed to lock database" >&2; exit 2 ;;
  none)   exit 0 ;;
  update) printf 'omarchy 4.0.0-1 -> 4.0.2-1\n'; exit 0 ;;
esac
SH
chmod +x "$stub_bin/checkupdates"

cat >"$stub_bin/pacman" <<'SH'
#!/bin/bash
[[ ${1:-} == -Qq && ${2:-} == omarchy ]] && { echo "omarchy"; exit 0; }
exit 1
SH
chmod +x "$stub_bin/pacman"

invoke() {
  OMARCHY_PATH=/usr/share/omarchy PATH="$stub_bin:$PATH" TEST_CHECKUPDATES_MODE="$1" \
    bash "$script" >"$test_tmp/out" 2>"$test_tmp/err"
  return $?
}

set +e
invoke error; rc=$?; set -e
(( rc == 2 )) || fail "checkupdates error exits 2" "got $rc"
pass "checkupdates error exits 2"

set +e
invoke none; rc=$?; set -e
(( rc == 1 )) || fail "no updates exits 1" "got $rc"
grep -F "Omarchy is up to date" "$test_tmp/out" >/dev/null ||
  fail "no updates prints up to date"
pass "no updates exits 1 with up to date message"

set +e
invoke update; rc=$?; set -e
(( rc == 0 )) || fail "updates found exits 0" "got $rc"
grep -F "omarchy 4.0.0-1 -> 4.0.2-1" "$test_tmp/out" >/dev/null ||
  fail "updates found prints update line"
pass "updates found exits 0 with update"