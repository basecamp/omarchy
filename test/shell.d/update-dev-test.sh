#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

stub_bin="$test_tmp/bin"
git_log="$test_tmp/git.log"
checkout="$test_tmp/checkout"
mkdir -p "$stub_bin" "$checkout"

cat >"$stub_bin/git" <<'SH'
#!/bin/bash

printf '%s\n' "$*" >>"$TEST_GIT_LOG"

[[ $1 == "-C" ]] || exit 1
shift 2

case "$1" in
  rev-parse)
    case "$2" in
      --is-inside-work-tree)
        [[ ${TEST_GIT_CHECKOUT:-yes} == "yes" ]] || exit 1
        echo true
        ;;
      --abbrev-ref)
        [[ ${TEST_GIT_UPSTREAM:-origin/quattro} != "none" ]] || exit 1
        echo "${TEST_GIT_UPSTREAM:-origin/quattro}"
        ;;
      *)
        exit 1
        ;;
    esac
    ;;
  pull)
    [[ $2 == "--ff-only" ]]
    ;;
  *)
    exit 1
    ;;
esac
SH
chmod +x "$stub_bin/git"

run_dev_update() {
  OMARCHY_PATH="$1" \
    TEST_GIT_LOG="$git_log" \
    PATH="$stub_bin:$PATH" \
    "$ROOT/bin/omarchy-update-dev"
}

# sudo env_reset (and similar clean environments) leave OMARCHY_PATH unset.
# The stock path must still be treated as a no-op so `sudo omarchy update` can
# continue past this step instead of dying under `set -u`.
run_dev_update_without_path() {
  env -u OMARCHY_PATH \
    TEST_GIT_LOG="$git_log" \
    PATH="$stub_bin:$PATH" \
    "$ROOT/bin/omarchy-update-dev"
}

: >"$git_log"
run_dev_update /usr/share/omarchy
[[ ! -s $git_log ]] || fail "package-backed updates do not invoke git" "$(cat "$git_log")"
pass "package-backed updates skip the dev checkout step"

: >"$git_log"
run_dev_update_without_path >"$test_tmp/unset.out" 2>"$test_tmp/unset.err" ||
  fail "unset OMARCHY_PATH must not abort under set -u" "$(cat "$test_tmp/unset.err")"
[[ ! -s $git_log ]] || fail "unset OMARCHY_PATH is treated as the stock install" "$(cat "$git_log")"
if grep -q 'unbound variable' "$test_tmp/unset.err"; then
  fail "unset OMARCHY_PATH must not raise an unbound-variable error" "$(cat "$test_tmp/unset.err")"
fi
pass "unset OMARCHY_PATH (sudo env_reset) skips the dev checkout step"

: >"$git_log"
OMARCHY_PATH= TEST_GIT_LOG="$git_log" PATH="$stub_bin:$PATH" \
  "$ROOT/bin/omarchy-update-dev" >"$test_tmp/empty.out" 2>"$test_tmp/empty.err" ||
  fail "empty OMARCHY_PATH must not abort under set -u" "$(cat "$test_tmp/empty.err")"
[[ ! -s $git_log ]] || fail "empty OMARCHY_PATH is treated as the stock install" "$(cat "$git_log")"
pass "empty OMARCHY_PATH skips the dev checkout step"

: >"$git_log"
run_dev_update "$checkout"
grep -Fx -- "-C $checkout pull --ff-only" "$git_log" >/dev/null ||
  fail "dev checkout update pulls its upstream with fast-forward only" "$(cat "$git_log")"
pass "dev checkout update pulls its configured upstream"

: >"$git_log"
TEST_GIT_UPSTREAM=none run_dev_update "$checkout"
if grep -q ' pull ' "$git_log"; then
  fail "dev checkout without an upstream is not pulled" "$(cat "$git_log")"
fi
pass "dev checkout without an upstream is skipped safely"

: >"$git_log"
if TEST_GIT_CHECKOUT=no run_dev_update "$checkout" >"$test_tmp/invalid.out" 2>"$test_tmp/invalid.err"; then
  fail "invalid dev checkout fails the update"
fi
grep -F "OMARCHY_PATH is not a git checkout: $checkout" "$test_tmp/invalid.err" >/dev/null ||
  fail "invalid dev checkout reports the configured path" "$(cat "$test_tmp/invalid.err")"
pass "invalid dev checkout fails with a useful error"

grep -qE '^ *omarchy-update-dev$' "$ROOT/bin/omarchy-update" ||
  fail "top-level update includes the dev checkout step"
pass "top-level update includes the dev checkout step"
