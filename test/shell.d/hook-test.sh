#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"
source "$ROOT/bin/omarchy-hook"

umask 022

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

: >"$hook_log"
mkdir -p "$core_root/hooks/stdin-event.d"
printf '%s\n' \
  '#!/bin/bash' \
  'IFS= read -r input || true' \
  'printf "core-read:%s\n" "$input" >>"$HOOK_LOG"' \
  >"$core_root/hooks/stdin-event.d/10-read"
make_hook "$vendor_one/omarchy/hooks/stdin-event.d/20-vendor" "vendor-after-read"
make_hook "$test_home/.config/omarchy/hooks/stdin-event.d/30-user" "user-after-read"
printf '%s\n' caller-input | \
  HOME="$test_home" \
    OMARCHY_PATH="$core_root" \
    XDG_DATA_DIRS="$vendor_one" \
    HOOK_LOG="$hook_log" \
    "$ROOT/bin/omarchy-hook" stdin-event
expected_stdin_order=$(printf '%s\n' \
  core-read:caller-input \
  vendor-after-read \
  user-after-read)
assert_lines "hooks inherit caller stdin without consuming root discovery" "$expected_stdin_order"

: >"$hook_log"
make_hook "$core_root/escaped-event" "escaped-event"
if HOME="$test_home" OMARCHY_PATH="$core_root" XDG_DATA_DIRS="$vendor_one" HOOK_LOG="$hook_log" \
  "$ROOT/bin/omarchy-hook" ../escaped-event >/dev/null 2>&1; then
  fail "hook runner rejects a traversing event name"
fi
[[ ! -s $hook_log ]] || fail "a traversing event name executes no hook"
pass "hook runner rejects a traversing event name"

if HOME="$test_home" OMARCHY_PATH="$core_root" XDG_DATA_DIRS="$vendor_one" HOOK_LOG="$hook_log" \
  "$ROOT/bin/omarchy-hook" "" >/dev/null 2>&1; then
  fail "hook runner rejects an empty event name"
fi
pass "hook runner rejects an empty event name"

install_source="$test_tmp/install-source"
make_hook "$install_source" "installed-hook"
if HOME="$test_home" "$ROOT/bin/omarchy-hook-install" ../escaped "$install_source" >/dev/null 2>&1; then
  fail "hook installer rejects a traversing event name"
fi
[[ ! -e $test_home/.config/omarchy/escaped.d/install-source ]] || fail "hook installer writes nothing for a traversing event name"
pass "hook installer rejects a traversing event name"

if HOME="$test_home" "$ROOT/bin/omarchy-hook-install" "" "$install_source" >/dev/null 2>&1; then
  fail "hook installer rejects an empty event name"
fi
[[ ! -e $test_home/.config/omarchy/hooks/.d/install-source ]] || fail "hook installer writes nothing for an empty event name"
pass "hook installer rejects an empty event name"

install_victim="$test_tmp/install-victim"
printf '%s\n' "victim" >"$install_victim"
mkdir -p "$test_home/.config/omarchy/hooks/install-event.d"
ln -s "$install_victim" "$test_home/.config/omarchy/hooks/install-event.d/install-source"
HOME="$test_home" "$ROOT/bin/omarchy-hook-install" install-event "$install_source" >/dev/null
[[ ! -L $test_home/.config/omarchy/hooks/install-event.d/install-source ]] || fail "hook installer replaces a destination symlink"
[[ $(<"$install_victim") == "victim" ]] || fail "hook installer leaves a destination symlink target untouched"
pass "hook installer replaces a destination symlink without following it"

: >"$hook_log"
unsafe_vendor="$test_tmp/shared-vendor"
make_hook "$unsafe_vendor/omarchy/hooks/trust-event.d/10-shared" "unsafe-package"
make_hook "$vendor_two/omarchy/hooks/trust-event.d/10-shared" "safe-package"
make_hook "$test_home/.config/omarchy/hooks/trust-event.d/20-user" "user-safe"
chmod 0777 "$unsafe_vendor"
HOME="$test_home" \
  OMARCHY_PATH="$core_root" \
  XDG_DATA_DIRS="$unsafe_vendor:$vendor_two" \
  HOOK_LOG="$hook_log" \
  "$ROOT/bin/omarchy-hook" trust-event 2>"$test_tmp/unsafe-hook.err"
expected_trusted_order=$(printf '%s\n' safe-package user-safe)
assert_lines "unsafe package roots are skipped without shadowing trusted hooks" "$expected_trusted_order"
grep -Fq "Skipping unsafe package hook path:" "$test_tmp/unsafe-hook.err" || fail "unsafe package root is reported"
pass "unsafe package root is reported"

: >"$hook_log"
make_hook "$vendor_one/omarchy/hooks/writable-event" "unsafe-writable-flat"
make_hook "$vendor_one/omarchy/hooks/writable-event.d/10-shared" "unsafe-writable-directory"
make_hook "$vendor_two/omarchy/hooks/writable-event" "safe-flat-after-writable"
make_hook "$vendor_two/omarchy/hooks/writable-event.d/10-shared" "safe-directory-after-writable"
make_hook "$test_home/.config/omarchy/hooks/writable-event.d/20-user" "user-after-writable"
chmod 0666 "$vendor_one/omarchy/hooks/writable-event"
chmod 0777 "$vendor_one/omarchy/hooks/writable-event.d"
HOME="$test_home" \
  OMARCHY_PATH="$core_root" \
  XDG_DATA_DIRS="$vendor_one:$vendor_two" \
  HOOK_LOG="$hook_log" \
  "$ROOT/bin/omarchy-hook" writable-event 2>"$test_tmp/writable-hook.err"
expected_writable_order=$(printf '%s\n' safe-flat-after-writable safe-directory-after-writable user-after-writable)
assert_lines "writable package paths do not shadow later trusted hooks" "$expected_writable_order"
writable_warning_count=$(grep -Fc "Skipping unsafe package hook path:" "$test_tmp/writable-hook.err")
(( writable_warning_count == 2 )) || fail "writable package paths are reported"
pass "writable package paths are reported"

: >"$hook_log"
make_hook "$test_tmp/outside-flat" "outside-flat"
make_hook "$test_tmp/outside-directory/10-outside" "outside-directory"
ln -s "$test_tmp/outside-flat" "$vendor_one/omarchy/hooks/symlink-event"
ln -s "$test_tmp/outside-directory" "$vendor_one/omarchy/hooks/symlink-event.d"
make_hook "$vendor_two/omarchy/hooks/symlink-event" "safe-flat-after-symlink"
make_hook "$test_home/.config/omarchy/hooks/symlink-event.d/20-user" "user-after-symlinks"
HOME="$test_home" \
  OMARCHY_PATH="$core_root" \
  XDG_DATA_DIRS="$vendor_one:$vendor_two" \
  HOOK_LOG="$hook_log" \
  "$ROOT/bin/omarchy-hook" symlink-event 2>"$test_tmp/symlink-hook.err"
expected_symlink_order=$(printf '%s\n' safe-flat-after-symlink user-after-symlinks)
assert_lines "package hook symlinks do not shadow later trusted hooks" "$expected_symlink_order"
symlink_warning_count=$(grep -Fc "Skipping unsafe package hook path:" "$test_tmp/symlink-hook.err")
(( symlink_warning_count == 2 )) || fail "unsafe package hook symlinks are reported"
pass "unsafe package hook symlinks are reported"

: >"$hook_log"
ln -s "$vendor_one" "$test_tmp/package-root-link"
HOME="$test_home" \
  OMARCHY_PATH="$core_root" \
  XDG_DATA_DIRS="$test_tmp/package-root-link" \
  HOOK_LOG="$hook_log" \
  "$ROOT/bin/omarchy-hook" vendor-event 2>"$test_tmp/symlink-root.err"
[[ ! -s $hook_log ]] || fail "a symlinked XDG package root executes no hook"
grep -Fq "Skipping unsafe package hook path:" "$test_tmp/symlink-root.err" || fail "a symlinked XDG package root is reported"
pass "symlinked XDG package roots are skipped"

: >"$hook_log"
newline_vendor="$test_tmp/vendor"$'\n'"newline"
make_hook "$newline_vendor/omarchy/hooks/newline-event" "newline-package"
HOME="$test_home" \
  OMARCHY_PATH="$core_root" \
  XDG_DATA_DIRS="$newline_vendor" \
  HOOK_LOG="$hook_log" \
  "$ROOT/bin/omarchy-hook" newline-event
assert_lines "newlines in XDG data paths are preserved" "newline-package"

: >"$hook_log"
make_hook "$vendor_one/omarchy/hooks/alias-event.d/10-shared" "vendor-before-user"
make_hook "$test_home/.config/omarchy/hooks/alias-event.d/10-shared" "user-still-runs"
HOME="$test_home" \
  OMARCHY_PATH="$test_home/.config/omarchy" \
  XDG_DATA_DIRS="$vendor_one" \
  HOOK_LOG="$hook_log" \
  "$ROOT/bin/omarchy-hook" alias-event
expected_alias_order=$(printf '%s\n' vendor-before-user user-still-runs)
assert_lines "the canonical user root always runs last as the user layer" "$expected_alias_order"

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
