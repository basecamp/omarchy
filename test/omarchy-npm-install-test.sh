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

cleanup() {
  [[ -n $TMPDIR && -d $TMPDIR ]] && rm -rf "$TMPDIR"
}
trap cleanup EXIT

TMPDIR=$(mktemp -d)
HOME="$TMPDIR/home" "$ROOT/bin/omarchy-npm-install" @openai/codex codex
wrapper="$TMPDIR/home/.local/bin/codex"

[[ -x $wrapper ]] || fail "npm wrapper is generated"
pass "npm wrapper is generated"

if ! grep -q "npm_config_minimum_release_age=7200" "$wrapper"; then
  fail "npm wrapper configures pnpm minimum release age"
fi
pass "npm wrapper configures pnpm minimum release age"

if ! grep -q "npm_config_dlx_cache_max_age=7200" "$wrapper"; then
  fail "npm wrapper configures pnpm dlx cache max age"
fi
pass "npm wrapper configures pnpm dlx cache max age"

if grep -q "PNPM_CONFIG_MINIMUM_RELEASE_AGE" "$wrapper"; then
  fail "npm wrapper does not use ignored PNPM_CONFIG env vars"
fi
pass "npm wrapper does not use ignored PNPM_CONFIG env vars"

removed_flag="--force""-update"

if grep -q -- "$removed_flag" "$wrapper"; then
  fail "npm wrapper does not expose removed force update flag"
fi
pass "npm wrapper does not expose removed force update flag"

if ! grep -q "npm_config_dlx_cache_max_age=0" "$wrapper"; then
  fail "npm wrapper update bypasses dlx cache"
fi
pass "npm wrapper update bypasses dlx cache"

if ! grep -q "npm_config_minimum_release_age=0" "$wrapper"; then
  fail "npm wrapper update bypasses minimum release age"
fi
pass "npm wrapper update bypasses minimum release age"

if ! grep -q "wrapper_update=1" "$wrapper"; then
  fail "npm wrapper maps update to wrapper update"
fi
pass "npm wrapper maps update to wrapper update"

if ! grep -q "version_file=" "$wrapper"; then
  fail "npm wrapper persists update version"
fi
pass "npm wrapper persists update version"

stub_bin="$TMPDIR/bin"
node_root="$TMPDIR/node"
package_bin="$TMPDIR/package-bin"
pnpm_log="$TMPDIR/pnpm.log"
package_args="$TMPDIR/package-args"
mkdir -p "$stub_bin" "$node_root/bin"

cat > "$stub_bin/mise" <<'SH'
#!/bin/bash
if [[ $1 == "where" && $2 == "node@latest" ]]; then
  printf '%s\n' "$OMARCHY_NPM_TEST_NODE_ROOT"
  exit 0
fi

exit 1
SH

cat > "$stub_bin/omarchy-cmd-missing" <<'SH'
#!/bin/bash
exit 1
SH

cat > "$stub_bin/pnpm" <<'SH'
#!/bin/bash
printf 'min_age=%s dlx_cache=%s args=%s\n' "${npm_config_minimum_release_age:-}" "${npm_config_dlx_cache_max_age:-}" "$*" >>"$OMARCHY_NPM_TEST_PNPM_LOG"

if [[ $1 == "view" ]]; then
  printf '1.2.3\n'
  exit 0
fi

if [[ $1 == "dlx" && $4 == "true" ]]; then
  exit 0
fi

if [[ $1 == "dlx" && $4 == "which" ]]; then
  printf '%s\n' "$OMARCHY_NPM_TEST_PACKAGE_BIN"
  exit 0
fi

exit 1
SH

cat > "$package_bin" <<'SH'
#!/bin/bash
printf '%s\n' "$*" >"$OMARCHY_NPM_TEST_PACKAGE_ARGS"
SH

chmod +x "$stub_bin/mise" "$stub_bin/omarchy-cmd-missing" "$stub_bin/pnpm" "$package_bin"

OMARCHY_NPM_TEST_NODE_ROOT="$node_root" \
OMARCHY_NPM_TEST_PACKAGE_BIN="$package_bin" \
OMARCHY_NPM_TEST_PACKAGE_ARGS="$package_args" \
OMARCHY_NPM_TEST_PNPM_LOG="$pnpm_log" \
PATH="$stub_bin:$PATH" \
  "$wrapper" -s danger-full-access update alpha beta

if ! grep -q "dlx_cache=0" "$pnpm_log"; then
  fail "update sets pnpm dlx cache age to zero"
fi
pass "update sets pnpm dlx cache age to zero"

if ! grep -q "min_age=0" "$pnpm_log"; then
  fail "update sets pnpm minimum release age to zero"
fi
pass "update sets pnpm minimum release age to zero"

if ! grep -q "args=dlx --package @openai/codex@1.2.3 true" "$pnpm_log"; then
  fail "update uses resolved latest package version"
fi
pass "update uses resolved latest package version"

if [[ -f $package_args ]]; then
  fail "update does not run the package bin"
fi
pass "update does not run the package bin"

rm -f "$pnpm_log" "$package_args"
OMARCHY_NPM_TEST_NODE_ROOT="$node_root" \
OMARCHY_NPM_TEST_PACKAGE_BIN="$package_bin" \
OMARCHY_NPM_TEST_PACKAGE_ARGS="$package_args" \
OMARCHY_NPM_TEST_PNPM_LOG="$pnpm_log" \
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

if ! grep -q "args=dlx --package @openai/codex@1.2.3 true" "$pnpm_log"; then
  fail "wrapper update uses resolved latest package version"
fi
pass "wrapper update uses resolved latest package version"

if [[ -f $package_args ]]; then
  fail "wrapper update does not run package self-updater"
fi
pass "wrapper update does not run package self-updater"

rm -f "$pnpm_log" "$package_args"
OMARCHY_NPM_TEST_NODE_ROOT="$node_root" \
OMARCHY_NPM_TEST_PACKAGE_BIN="$package_bin" \
OMARCHY_NPM_TEST_PACKAGE_ARGS="$package_args" \
OMARCHY_NPM_TEST_PNPM_LOG="$pnpm_log" \
PATH="$stub_bin:$PATH" \
  "$wrapper" gamma

if ! grep -q "args=dlx --package @openai/codex@1.2.3 true" "$pnpm_log"; then
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
