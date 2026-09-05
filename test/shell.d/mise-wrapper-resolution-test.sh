#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

migration="$ROOT/migrations/1787809285.sh"
test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT

home="$test_dir/home"
bin_dir="$home/.local/bin"
stub_bin="$test_dir/bin"
resolved_bin="$test_dir/resolved"
mise_log="$test_dir/mise.log"
tool_log="$test_dir/tool.log"
mkdir -p "$bin_dir" "$stub_bin" "$resolved_bin"

cat >"$stub_bin/mise" <<'SH'
#!/bin/bash

printf '%s\n' "$*" >>"$MISE_TEST_LOG"

case "$1" in
  use)
    exit 0
    ;;
  which)
    if (( ${MISE_TEST_WHICH_FAIL:-0} )); then
      exit 1
    fi
    printf '%s\n' "$MISE_TEST_RESOLVED_BIN"
    ;;
  x)
    shift 2
    [[ $1 == "--" ]] || exit 2
    shift
    [[ $1 == "$MISE_TEST_RESOLVED_BIN" ]] || exit 3
    export MISE_TEST_RUNTIME=present
    exec "$@"
    ;;
  *)
    exit 4
    ;;
esac
SH

cat >"$resolved_bin/ghui" <<'SH'
#!/bin/bash
printf '%s\0' "$MISE_TEST_RUNTIME" "$@" >"$MISE_TEST_TOOL_LOG"
SH
chmod +x "$stub_bin/mise" "$resolved_bin/ghui"

export MISE_TEST_LOG="$mise_log"
export MISE_TEST_RESOLVED_BIN="$resolved_bin/ghui"
export MISE_TEST_TOOL_LOG="$tool_log"

HOME="$home" "$ROOT/bin/omarchy-mise-install" npm:@kitlangton/ghui ghui
PATH="$bin_dir:$stub_bin:/usr/bin" "$bin_dir/ghui" first "two words"

grep -qx 'use -g --quiet npm:@kitlangton/ghui' "$mise_log" ||
  fail "wrapper activates its mise package quietly"
grep -qx 'which ghui --tool=npm:@kitlangton/ghui' "$mise_log" ||
  fail "wrapper resolves the bin from its package"
grep -qx "x npm:@kitlangton/ghui -- $resolved_bin/ghui first two words" "$mise_log" ||
  fail "wrapper gives mise x the resolved path"
mapfile -d '' -t tool_args <"$tool_log"
[[ ${tool_args[0]} == "present" && ${tool_args[1]} == "first" && ${tool_args[2]} == "two words" ]] ||
  fail "wrapper retains mise's runtime environment and argument boundaries"
pass "wrapper executes a package-scoped absolute path through mise"

: >"$mise_log"
if MISE_TEST_WHICH_FAIL=1 PATH="$bin_dir:$stub_bin:/usr/bin" "$bin_dir/ghui" >/dev/null 2>&1; then
  fail "wrapper exits when mise cannot resolve the requested bin"
fi
if grep -q '^x ' "$mise_log"; then
  fail "wrapper does not invoke mise x after resolution fails"
fi
pass "wrapper stops when its bin cannot be resolved"

cat >"$bin_dir/codex" <<'SH'
#!/bin/bash
export MISE_MINIMUM_RELEASE_AGE=0
mise use -g --quiet "codex" || exit 1
exec mise x "codex" -- "codex" "$@"
SH
chmod +x "$bin_dir/codex"

cat >"$bin_dir/customized" <<'SH'
#!/bin/bash
export MISE_MINIMUM_RELEASE_AGE=0
export CUSTOMIZED=1
mise use -g --quiet "customized" || exit 1
exec mise x "customized" -- "customized" "$@"
SH
chmod +x "$bin_dir/customized"
customized_before=$(<"$bin_dir/customized")

run_migration() {
  HOME="$home" PATH="$ROOT/bin:$stub_bin:/usr/bin" bash -euo pipefail "$migration" >/dev/null
}

run_migration

grep -qF 'bin_path=$(mise which "codex" --tool="codex") || exit 1' "$bin_dir/codex" ||
  fail "migration regenerates a current mise wrapper with resolved execution"
grep -qF 'exec mise x "codex" -- "$bin_path" "$@"' "$bin_dir/codex" ||
  fail "migrated wrapper passes the resolved path to mise x"
[[ $(<"$bin_dir/customized") == "$customized_before" ]] ||
  fail "migration leaves a customized wrapper alone"
pass "migration only regenerates the exact current wrapper template"

before=$(<"$bin_dir/codex")
run_migration
[[ $(<"$bin_dir/codex") == "$before" ]] || fail "migration is idempotent"
pass "migration is idempotent"

empty_home="$test_dir/empty-home"
mkdir -p "$empty_home"
HOME="$empty_home" PATH="$ROOT/bin:$stub_bin:/usr/bin" bash -euo pipefail "$migration" >/dev/null ||
  fail "migration succeeds when ~/.local/bin is missing"
pass "migration succeeds when ~/.local/bin is missing"
