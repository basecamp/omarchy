#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

stub_bin="$test_tmp/bin"
root_fs="$test_tmp/fs"
log_file="$test_tmp/refresh.log"
mkdir -p "$stub_bin" "$root_fs/etc/pacman.d"

cat >"$stub_bin/sudo" <<'STUB'
#!/bin/bash

printf 'sudo' >>"$OMARCHY_REFRESH_TEST_LOG"
for arg in "$@"; do
  printf '\t%s' "$arg" >>"$OMARCHY_REFRESH_TEST_LOG"
done
printf '\n' >>"$OMARCHY_REFRESH_TEST_LOG"

action=$1
shift

case "$action" in
  cp)
    if [[ ${OMARCHY_REFRESH_TEST_CHANNEL_COPY_FAIL:-0} == "1" && $2 == "$OMARCHY_PATH/default/pacman/mirrorlist-stable" ]]; then
      exit 1
    fi

    rerooted=()
    for arg in "$@"; do
      case "$arg" in
        /etc/*) rerooted+=("$OMARCHY_REFRESH_TEST_ROOT$arg") ;;
        *) rerooted+=("$arg") ;;
      esac
    done
    command cp "${rerooted[@]}"
    ;;
  env)
    [[ ${OMARCHY_REFRESH_TEST_PACMAN_FAIL:-0} == "0" ]]
    ;;
  mktemp | rm)
    command "$action" "$@"
    ;;
  *)
    exit 1
    ;;
esac
STUB
chmod +x "$stub_bin/sudo"

cat >"$stub_bin/omarchy-hook" <<'STUB'
#!/bin/bash

printf 'hook\t%s\n' "$*" >>"$OMARCHY_REFRESH_TEST_LOG"
[[ ${OMARCHY_REFRESH_TEST_HOOK_FAIL:-0} == "0" ]]
STUB
chmod +x "$stub_bin/omarchy-hook"

reset_config() {
  printf 'original pacman config\n' >"$root_fs/etc/pacman.conf"
  printf 'original mirrorlist\n' >"$root_fs/etc/pacman.d/mirrorlist"
  : >"$log_file"
}

run_refresh() {
  OMARCHY_PATH="$ROOT" \
    OMARCHY_REFRESH_TEST_LOG="$log_file" \
    OMARCHY_REFRESH_TEST_ROOT="$root_fs" \
    PATH="$stub_bin:$PATH" \
    "$ROOT/bin/omarchy-refresh-pacman" stable
}

assert_original_config() {
  grep -qx 'original pacman config' "$root_fs/etc/pacman.conf" ||
    fail "$1" "pacman.conf: $(cat "$root_fs/etc/pacman.conf")"
  grep -qx 'original mirrorlist' "$root_fs/etc/pacman.d/mirrorlist" ||
    fail "$1" "mirrorlist: $(cat "$root_fs/etc/pacman.d/mirrorlist")"
  pass "$1"
}

reset_config
if OMARCHY_REFRESH_TEST_PACMAN_FAIL=1 run_refresh >"$test_tmp/pacman.out" 2>"$test_tmp/pacman.err"; then
  fail "a failed package refresh returns non-zero"
fi

assert_original_config "a failed package refresh restores both pacman configuration files"
grep -q 'Previous pacman configuration restored.' "$test_tmp/pacman.err" ||
  fail "a failed package refresh reports the rollback" "$(cat "$test_tmp/pacman.err")"
pass "a failed package refresh reports the rollback"

reset_config
if OMARCHY_REFRESH_TEST_CHANNEL_COPY_FAIL=1 run_refresh >"$test_tmp/channel-copy.out" 2>"$test_tmp/channel-copy.err"; then
  fail "a failed channel copy returns non-zero"
fi

assert_original_config "a partial channel copy restores both pacman configuration files"
if grep -q $'^hook\t' "$log_file" || grep -q $'^sudo\tenv\t' "$log_file"; then
  fail "the hook and pacman do not run after a failed channel copy" "$(cat "$log_file")"
fi
pass "the hook and pacman do not run after a failed channel copy"

reset_config
if OMARCHY_REFRESH_TEST_HOOK_FAIL=1 run_refresh >"$test_tmp/hook.out" 2>"$test_tmp/hook.err"; then
  fail "a failed pre-refresh hook returns non-zero"
fi

assert_original_config "a failed pre-refresh hook restores both pacman configuration files"
if grep -q $'^sudo\tenv\t' "$log_file"; then
  fail "pacman does not run after a failed pre-refresh hook" "$(cat "$log_file")"
fi
pass "pacman does not run after a failed pre-refresh hook"

reset_config
run_refresh >"$test_tmp/success.out" 2>"$test_tmp/success.err"

cmp -s "$ROOT/default/pacman/pacman-stable.conf" "$root_fs/etc/pacman.conf" ||
  fail "a successful refresh keeps the selected pacman config"
cmp -s "$ROOT/default/pacman/mirrorlist-stable" "$root_fs/etc/pacman.d/mirrorlist" ||
  fail "a successful refresh keeps the selected mirrorlist"
pass "a successful refresh keeps the selected pacman configuration"
