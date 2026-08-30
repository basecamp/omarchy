#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"
source "$ROOT/bin/omarchy-hook"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

test_home="$test_tmp/home"
core_root="$test_tmp/core"
vendor_one="$test_tmp/vendor-one"
vendor_two="$test_tmp/vendor-two"
hook_log="$test_tmp/hooks.log"
mkdir -p "$test_home" "$core_root" "$vendor_one" "$vendor_two"

make_hook() {
  local path=$1
  local label=$2
  local status=${3:-0}

  mkdir -p "$(dirname -- "$path")"
  printf '#!/bin/bash\nprintf "%%s\\n" "%s" >>"$HOOK_LOG"\nexit %s\n' "$label" "$status" >"$path"
}

assert_lines() {
  local description=$1
  local expected=$2
  local actual

  actual=$(<"$hook_log")
  if [[ $actual == "$expected" ]]; then
    pass "$description"
  else
    fail "$description" "expected:\n$expected\nactual:\n$actual"
  fi
}

make_hook "$vendor_one/omarchy/hooks/test-event" "vendor-one-flat"
make_hook "$vendor_one/omarchy/hooks/test-event.d/10-failing" "vendor-one-failing" 1
make_hook "$vendor_one/omarchy/hooks/test-event.d/20-after-failure" "vendor-one-after-failure"
make_hook "$vendor_one/omarchy/hooks/test-event.d/30-shared" "vendor-one-shared"
make_hook "$vendor_one/omarchy/hooks/test-event.d/30-ignored.sample" "sample"
make_hook "$vendor_one/omarchy/hooks/test-event.d/40-vendor-shared" "vendor-one-xdg-shared"
make_hook "$vendor_two/omarchy/hooks/test-event.d/10-vendor-two" "vendor-two"
make_hook "$vendor_two/omarchy/hooks/test-event.d/40-vendor-shared" "vendor-two-xdg-shared"
make_hook "$core_root/hooks/test-event" "core-flat"
make_hook "$core_root/hooks/test-event.d/10-core" "core-directory"
make_hook "$core_root/hooks/test-event.d/30-shared" "core-shared"
make_hook "$test_home/.config/omarchy/hooks/test-event" "user-flat"
make_hook "$test_home/.config/omarchy/hooks/test-event.d/10-user" "user-directory"
make_hook "$test_home/.config/omarchy/hooks/test-event.d/30-shared" "user-shared"

hook_output=$(
  HOME="$test_home" \
    OMARCHY_PATH="$core_root" \
    XDG_DATA_DIRS="$vendor_one:$vendor_two" \
    HOOK_LOG="$hook_log" \
    "$ROOT/bin/omarchy-hook" test-event
)

expected_order=$(printf '%s\n' \
  core-flat \
  core-directory \
  core-shared \
  vendor-one-failing \
  vendor-one-after-failure \
  vendor-one-xdg-shared \
  vendor-two \
  user-flat \
  user-directory \
  user-shared)
assert_lines "vendor, dev-tree, flat, directory, and user hooks run in order" "$expected_order"

[[ $hook_output == *"Hook failed: $vendor_one/omarchy/hooks/test-event.d/10-failing"* ]] || fail "hook failure is reported"
pass "hook failure is reported"
[[ $hook_output != *sample* ]] || fail "sample hook is skipped"
pass "sample hook is skipped and later hooks continue"

if grep -Fxq core-shared "$hook_log" && grep -Fxq user-shared "$hook_log" && ! grep -Fq vendor-one-shared "$hook_log"; then
  pass "core hooks shadow vendor duplicates while matching user hooks still run"
else
  fail "core hooks shadow vendor duplicates while matching user hooks still run"
fi

if grep -Fxq vendor-one-xdg-shared "$hook_log" && ! grep -Fq vendor-two-xdg-shared "$hook_log"; then
  pass "earlier XDG data directories shadow later duplicate hook names"
else
  fail "earlier XDG data directories shadow later duplicate hook names"
fi

: >"$hook_log"
make_hook "$vendor_one/omarchy/hooks/vendor-event" "vendor-flat"
HOME="$test_tmp/empty-home" \
  OMARCHY_PATH="$core_root" \
  XDG_DATA_DIRS="$vendor_one" \
  HOOK_LOG="$hook_log" \
  "$ROOT/bin/omarchy-hook" vendor-event
assert_lines "package-managed flat hook runs" "vendor-flat"

: >"$hook_log"
production_root="$test_tmp/production-data"
make_hook "$production_root/omarchy/hooks/test-event.d/10-once" "production-once"
HOME="$test_tmp/empty-home" \
  OMARCHY_PATH="$production_root/omarchy" \
  XDG_DATA_DIRS="$production_root:$production_root/" \
  HOOK_LOG="$hook_log" \
  "$ROOT/bin/omarchy-hook" test-event
assert_lines "production OMARCHY_PATH and duplicate XDG roots run once" "production-once"

root_list() {
  local root
  while IFS= read -r -d '' root; do
    printf '%s\n' "$root"
  done < <(omarchy_hook_roots)
}

HOME="$test_home"
OMARCHY_PATH="$core_root"
unset XDG_DATA_DIRS
unset_roots=$(root_list)
expected_default_roots=$(printf '%s\n' \
  "$core_root/hooks" \
  /usr/local/share/omarchy/hooks \
  /usr/share/omarchy/hooks \
  "$test_home/.config/omarchy/hooks")
[[ $unset_roots == "$expected_default_roots" ]] || fail "unset XDG_DATA_DIRS uses standard defaults" "expected:\n$expected_default_roots\nactual:\n$unset_roots"
pass "unset XDG_DATA_DIRS uses standard defaults"

XDG_DATA_DIRS=
empty_roots=$(root_list)
[[ $empty_roots == "$expected_default_roots" ]] || fail "empty XDG_DATA_DIRS uses standard defaults" "expected:\n$expected_default_roots\nactual:\n$empty_roots"
pass "empty XDG_DATA_DIRS uses standard defaults"

ln -s "$vendor_one" "$test_tmp/vendor-one-link"
XDG_DATA_DIRS="relative::also-relative:$vendor_one:$vendor_one/:$test_tmp/vendor-one-link"
filtered_roots=$(root_list)
expected_filtered_roots=$(printf '%s\n' \
  "$core_root/hooks" \
  "$vendor_one/omarchy/hooks" \
  "$test_home/.config/omarchy/hooks")
[[ $filtered_roots == "$expected_filtered_roots" ]] || fail "relative, empty, and canonical duplicate data entries are ignored" "expected:\n$expected_filtered_roots\nactual:\n$filtered_roots"
pass "relative, empty, and canonical duplicate data entries are ignored"
