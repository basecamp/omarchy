#!/bin/bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
TMPDIR=""

export PATH="$ROOT/bin:$PATH"

pass() {
  printf 'ok - %s\n' "$1"
}

fail() {
  printf 'not ok - %s\n' "$1" >&2
  exit 1
}

assert_file_contains() {
  local description="$1"
  local file="$2"
  local expected="$3"

  if ! grep -Fq "$expected" "$file"; then
    printf 'Expected %s to contain: %s\n' "$file" "$expected" >&2
    printf 'Actual file:\n' >&2
    sed -n '1,120p' "$file" >&2
    fail "$description"
  fi

  pass "$description"
}

cleanup() {
  [[ -n $TMPDIR && -d $TMPDIR ]] && rm -rf "$TMPDIR"
}
trap cleanup EXIT

TMPDIR=$(mktemp -d)
HOME="$TMPDIR/home" "$ROOT/bin/omarchy-npm-install" @openai/codex codex
wrapper="$TMPDIR/home/.local/bin/codex"
runtime="$ROOT/bin/omarchy-npm-run"

[[ -x $wrapper ]] || fail "npm wrapper is generated"
pass "npm wrapper is generated"

assert_file_contains "npm wrapper defaults bin to command name" "$wrapper" 'exec omarchy-npm-run "@openai/codex" "codex" "codex" "$@"'

if grep -q "pnpm dlx" "$wrapper"; then
  fail "npm wrapper does not inline pnpm runtime"
fi
pass "npm wrapper does not inline pnpm runtime"

HOME="$TMPDIR/home" "$ROOT/bin/omarchy-npm-install" playwright playwright-cli playwright
assert_file_contains "npm wrapper records explicit package bin" "$TMPDIR/home/.local/bin/playwright-cli" 'exec omarchy-npm-run "playwright" "playwright-cli" "playwright" "$@"'

assert_file_contains "npm runtime defines pin ttl" "$runtime" "pin_ttl=7200"
assert_file_contains "npm runtime configures pnpm minimum release age" "$runtime" 'npm_config_minimum_release_age=$pin_ttl'
assert_file_contains "npm runtime configures pnpm dlx cache max age" "$runtime" 'npm_config_dlx_cache_max_age=$pin_ttl'

if grep -q "PNPM_CONFIG_MINIMUM_RELEASE_AGE" "$runtime"; then
  fail "npm runtime does not use ignored PNPM_CONFIG env vars"
fi
pass "npm runtime does not use ignored PNPM_CONFIG env vars"

removed_flag="--force""-update"

if grep -q -- "$removed_flag" "$runtime"; then
  fail "npm runtime does not expose removed force update flag"
fi
pass "npm runtime does not expose removed force update flag"

if grep -q " which " "$runtime"; then
  fail "npm runtime does not discover package bins dynamically"
fi
pass "npm runtime does not discover package bins dynamically"

stub_bin="$TMPDIR/bin"
node_root="$TMPDIR/node"
state_home="$TMPDIR/state"
pnpm_log="$TMPDIR/pnpm.log"
package_args="$TMPDIR/package-args"
version_file="$state_home/omarchy/npm-wrappers/codex.version"
mkdir -p "$stub_bin" "$node_root/bin"

cat >"$stub_bin/mise" <<'SH'
#!/bin/bash
if [[ $1 == "where" && $2 == "node@latest" ]]; then
  printf '%s\n' "$OMARCHY_NPM_TEST_NODE_ROOT"
  exit 0
fi

exit 1
SH

cat >"$stub_bin/omarchy-cmd-missing" <<'SH'
#!/bin/bash
exit 1
SH

cat >"$stub_bin/pnpm" <<'SH'
#!/bin/bash
printf 'min_age=%s dlx_cache=%s args=%s\n' "${npm_config_minimum_release_age:-}" "${npm_config_dlx_cache_max_age:-}" "$*" >>"$OMARCHY_NPM_TEST_PNPM_LOG"

if [[ $1 == "view" ]]; then
  printf '1.2.3\n'
  exit 0
fi

if [[ $1 == "dlx" ]]; then
  if [[ $4 == "true" ]]; then
    exit 0
  fi

  shift 4
  printf '%s\n' "$*" >"$OMARCHY_NPM_TEST_PACKAGE_ARGS"
  exit 0
fi

exit 1
SH

chmod +x "$stub_bin/mise" "$stub_bin/omarchy-cmd-missing" "$stub_bin/pnpm"

OMARCHY_NPM_TEST_NODE_ROOT="$node_root" \
OMARCHY_NPM_TEST_PACKAGE_ARGS="$package_args" \
OMARCHY_NPM_TEST_PNPM_LOG="$pnpm_log" \
HOME="$TMPDIR/home" \
XDG_STATE_HOME="$state_home" \
PATH="$stub_bin:$PATH" \
  "$wrapper" -s danger-full-access update alpha beta

if ! grep -Fq "args=dlx --package @openai/codex codex -s danger-full-access update alpha beta" "$pnpm_log"; then
  fail "non-leading update is forwarded to package bin"
fi
pass "non-leading update is forwarded to package bin"

if ! grep -q "dlx_cache=7200" "$pnpm_log"; then
  fail "normal run uses pnpm dlx cache age"
fi
pass "normal run uses pnpm dlx cache age"

if ! grep -q "min_age=7200" "$pnpm_log"; then
  fail "normal run uses pnpm minimum release age"
fi
pass "normal run uses pnpm minimum release age"

if [[ $(<"$package_args") != "-s danger-full-access update alpha beta" ]]; then
  fail "normal run forwards package args"
fi
pass "normal run forwards package args"

if [[ -f $version_file ]]; then
  fail "non-leading update does not pin wrapper version"
fi
pass "non-leading update does not pin wrapper version"

rm -f "$pnpm_log" "$package_args"
OMARCHY_NPM_TEST_NODE_ROOT="$node_root" \
OMARCHY_NPM_TEST_PACKAGE_ARGS="$package_args" \
OMARCHY_NPM_TEST_PNPM_LOG="$pnpm_log" \
HOME="$TMPDIR/home" \
XDG_STATE_HOME="$state_home" \
PATH="$stub_bin:$PATH" \
  "$wrapper" update alpha

if ! grep -Fq "args=dlx --package @openai/codex codex update alpha" "$pnpm_log"; then
  fail "update with extra args is forwarded to package bin"
fi
pass "update with extra args is forwarded to package bin"

if [[ -f $version_file ]]; then
  fail "update with extra args does not pin wrapper version"
fi
pass "update with extra args does not pin wrapper version"

rm -f "$pnpm_log" "$package_args"
OMARCHY_NPM_TEST_NODE_ROOT="$node_root" \
OMARCHY_NPM_TEST_PACKAGE_ARGS="$package_args" \
OMARCHY_NPM_TEST_PNPM_LOG="$pnpm_log" \
HOME="$TMPDIR/home" \
XDG_STATE_HOME="$state_home" \
PATH="$stub_bin:$PATH" \
  "$wrapper" update

if ! grep -q "dlx_cache=0" "$pnpm_log"; then
  fail "wrapper update refreshes pnpm dlx cache"
fi
pass "wrapper update refreshes pnpm dlx cache"

if ! grep -q "min_age=0" "$pnpm_log"; then
  fail "wrapper update bypasses pnpm minimum release age"
fi
pass "wrapper update bypasses pnpm minimum release age"

if ! grep -Fq "args=dlx --package @openai/codex@1.2.3 true" "$pnpm_log"; then
  fail "wrapper update uses resolved latest package version"
fi
pass "wrapper update uses resolved latest package version"

if [[ -f $package_args ]]; then
  fail "wrapper update does not run package bin"
fi
pass "wrapper update does not run package bin"

if [[ $(<"$version_file") != "1.2.3" ]]; then
  fail "wrapper update persists resolved version"
fi
pass "wrapper update persists resolved version"

rm -f "$pnpm_log" "$package_args"
OMARCHY_NPM_TEST_NODE_ROOT="$node_root" \
OMARCHY_NPM_TEST_PACKAGE_ARGS="$package_args" \
OMARCHY_NPM_TEST_PNPM_LOG="$pnpm_log" \
HOME="$TMPDIR/home" \
XDG_STATE_HOME="$state_home" \
PATH="$stub_bin:$PATH" \
  "$wrapper" gamma

if ! grep -Fq "args=dlx --package @openai/codex@1.2.3 codex gamma" "$pnpm_log"; then
  fail "wrapper reuses pinned update version"
fi
pass "wrapper reuses pinned update version"

if ! grep -q "min_age=0" "$pnpm_log"; then
  fail "wrapper bypasses minimum release age for pinned version"
fi
pass "wrapper bypasses minimum release age for pinned version"

if [[ $(<"$package_args") != "gamma" ]]; then
  fail "wrapper forwards args after pinned update"
fi
pass "wrapper forwards args after pinned update"

rm -f "$pnpm_log" "$package_args"
touch -d "@$(($(date +%s) - 7201))" "$version_file"
OMARCHY_NPM_TEST_NODE_ROOT="$node_root" \
OMARCHY_NPM_TEST_PACKAGE_ARGS="$package_args" \
OMARCHY_NPM_TEST_PNPM_LOG="$pnpm_log" \
HOME="$TMPDIR/home" \
XDG_STATE_HOME="$state_home" \
PATH="$stub_bin:$PATH" \
  "$wrapper" delta

if ! grep -Fq "args=dlx --package @openai/codex codex delta" "$pnpm_log"; then
  fail "wrapper drops expired pinned update version"
fi
pass "wrapper drops expired pinned update version"

if ! grep -q "min_age=7200" "$pnpm_log"; then
  fail "wrapper restores minimum release age after pin expiry"
fi
pass "wrapper restores minimum release age after pin expiry"

if [[ -f $version_file ]]; then
  fail "wrapper removes expired pinned version file"
fi
pass "wrapper removes expired pinned version file"
