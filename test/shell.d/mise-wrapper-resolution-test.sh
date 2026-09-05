#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

migration="$ROOT/migrations/1787809285.sh"
test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT

home="$test_dir/home"
bin_dir="$home/.local/bin"
stub_bin="$test_dir/bin"
package_bin="$test_dir/package-bin"
directory_bin="$test_dir/directory-bin"
wrong_bin="$test_dir/wrong-bin"
mise_log="$test_dir/mise.log"
tool_log="$test_dir/tool.log"
mkdir -p "$bin_dir" "$stub_bin" "$package_bin" "$directory_bin/pi" "$wrong_bin"

cat >"$stub_bin/mise" <<'SH'
#!/bin/bash

printf '%s\n' "$*" >>"$MISE_TEST_LOG"

case "$1" in
  use)
    exit 0
    ;;
  which)
    printf '%s\n' "$MISE_TEST_WRONG_BIN"
    ;;
  bin-paths)
    if (( ${MISE_TEST_BIN_PATHS_FAIL_AFTER_OUTPUT:-0} )); then
      printf '%s\n' "$MISE_TEST_PACKAGE_BIN"
      exit 42
    fi
    if (( ${MISE_TEST_BIN_PATHS_EMPTY:-0} )); then
      exit 0
    fi
    printf '%s\n' "$MISE_TEST_DIRECTORY_BIN" "$MISE_TEST_PACKAGE_BIN"
    ;;
  x)
    shift 2
    [[ $1 == "--" ]] || exit 2
    shift
    export MISE_TEST_RUNTIME=present
    exec "$@"
    ;;
  *)
    exit 4
    ;;
esac
SH

cat >"$package_bin/pi" <<'SH'
#!/bin/bash
printf '%s\0' "$MISE_TEST_RUNTIME" "$@" >"$MISE_TEST_TOOL_LOG"
SH
# A Node runtime may also provide `pi`; `mise which pi --tool=pi` can select it.
# The wrapper must stay inside the dedicated Pi package's bin paths instead.
cat >"$wrong_bin/pi" <<'SH'
#!/bin/bash
printf 'wrong-package\0' >"$MISE_TEST_TOOL_LOG"
SH
chmod +x "$stub_bin/mise" "$package_bin/pi" "$wrong_bin/pi"

export MISE_TEST_LOG="$mise_log"
export MISE_TEST_PACKAGE_BIN="$package_bin"
export MISE_TEST_DIRECTORY_BIN="$directory_bin"
export MISE_TEST_WRONG_BIN="$wrong_bin/pi"
export MISE_TEST_TOOL_LOG="$tool_log"

mkdir -p "$home/.local"
printf 'keep\n' >"$home/.local/sentinel"
for bad_command in ../sentinel . ..; do
  if HOME="$home" "$ROOT/bin/omarchy-mise-install" pi "$bad_command" pi >/dev/null 2>&1; then
    fail "wrapper generator rejects unsafe command name $bad_command"
  fi
done
[[ $(<"$home/.local/sentinel") == keep ]] ||
  fail "wrapper generator does not overwrite a path escaped through command-name"
pass "wrapper generator rejects unsafe command names"

if HOME="$home" "$ROOT/bin/omarchy-mise-install" pi escaped ../wrong-bin/pi >/dev/null 2>&1; then
  fail "wrapper generator rejects bin names that escape package bin directories"
fi
[[ ! -e $bin_dir/escaped ]] ||
  fail "wrapper generator does not write a wrapper for an escaping bin name"
pass "wrapper generator rejects escaping bin names"

HOME="$home" "$ROOT/bin/omarchy-mise-install" pi
grep -qF '[[ -n $bin_dir ]] || continue' "$bin_dir/pi" ||
  fail "wrapper skips empty package bin-directory entries"
PATH="$bin_dir:$stub_bin:/usr/bin" "$bin_dir/pi" first "two words"

grep -qx 'use -g --quiet pi' "$mise_log" ||
  fail "wrapper activates its mise package quietly"
grep -qx 'bin-paths pi' "$mise_log" ||
  fail "wrapper asks mise for the requested package's bin directories"
grep -qx "x pi -- $package_bin/pi first two words" "$mise_log" ||
  fail "wrapper gives mise x the package-scoped absolute path"
mapfile -d '' -t tool_args <"$tool_log"
[[ ${tool_args[0]} == "present" && ${tool_args[1]} == "first" && ${tool_args[2]} == "two words" ]] ||
  fail "wrapper executes the requested package's bin with its runtime environment and argument boundaries"
pass "wrapper ignores a same-named executable from another package"

: >"$mise_log"
if MISE_TEST_BIN_PATHS_FAIL_AFTER_OUTPUT=1 PATH="$bin_dir:$stub_bin:/usr/bin" "$bin_dir/pi" >/dev/null 2>&1; then
  fail "wrapper exits when mise bin-paths fails after writing output"
fi
if grep -q '^x ' "$mise_log"; then
  fail "wrapper does not invoke mise x after bin-paths fails"
fi
pass "wrapper stops when mise bin-paths fails after writing output"

: >"$mise_log"
error_log="$test_dir/error"
if MISE_TEST_BIN_PATHS_EMPTY=1 PATH="$bin_dir:$stub_bin:/usr/bin" "$bin_dir/pi" >/dev/null 2>"$error_log"; then
  fail "wrapper exits when mise cannot resolve the requested bin"
fi
grep -qx "pi: mise package 'pi' provides no executable 'pi'" "$error_log" ||
  fail "wrapper explains when its bin cannot be resolved"
pass "wrapper explains when its bin cannot be resolved"
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

grep -qF 'bin_paths=$(mise bin-paths "codex")' "$bin_dir/codex" ||
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
