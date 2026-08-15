#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

mock_bin="$test_tmp/bin"
test_home="$test_tmp/home"
probe_log="$test_tmp/editor-probes"
launch_log="$test_tmp/editor-launch"
shim_log="$test_tmp/cursor-shim"
mkdir -p "$mock_bin" "$test_home/.local/state/omarchy/defaults"

cat >"$mock_bin/cursor" <<'SH'
#!/bin/bash
touch "$OMARCHY_TEST_CURSOR_SHIM_LOG"
SH

cat >"$mock_bin/omarchy-pkg-present" <<'SH'
#!/bin/bash
[[ $1 == "cursor-bin" && ${OMARCHY_TEST_CURSOR_PACKAGE:-false} == "true" ]]
SH

cat >"$mock_bin/omarchy-cmd-present" <<'SH'
#!/bin/bash
printf '%s\n' "$1" >>"$OMARCHY_TEST_EDITOR_PROBE_LOG"
[[ $1 == "nvim" ]]
SH

cat >"$mock_bin/omarchy-notification-send" <<'SH'
#!/bin/bash
exit 0
SH

cat >"$mock_bin/omarchy-launch-tui" <<'SH'
#!/bin/bash
printf '%s\0' "$@" >"$OMARCHY_TEST_EDITOR_LAUNCH_LOG"
SH

chmod +x "$mock_bin"/*

export HOME="$test_home"
export PATH="$mock_bin:$ROOT/bin:$PATH"
export OMARCHY_TEST_CURSOR_SHIM_LOG="$shim_log"
export OMARCHY_TEST_EDITOR_PROBE_LOG="$probe_log"
export OMARCHY_TEST_EDITOR_LAUNCH_LOG="$launch_log"

if OMARCHY_TEST_CURSOR_PACKAGE=true omarchy-default-editor cursor >"$test_tmp/default-editor-output" 2>&1; then
  fail "Cursor Agent shim cannot satisfy Cursor IDE detection"
fi
grep -Fq "cursor-bin" "$test_tmp/default-editor-output" || fail "missing Cursor IDE diagnostic names its package"
grep -Fxq "/usr/bin/cursor" "$probe_log" || fail "default editor probes Cursor's packaged executable"
[[ ! -e $test_home/.local/state/omarchy/defaults/editor ]] || fail "Cursor shim is not saved as the default editor"
[[ ! -e $shim_log ]] || fail "Cursor IDE detection never executes a PATH-provided shim"
pass "Cursor Agent shim cannot satisfy Cursor IDE detection"

printf '%s\n' cursor >"$test_home/.local/state/omarchy/defaults/editor"
: >"$probe_log"
omarchy-launch-editor "$test_home/project"

mapfile -d '' -t launch_args <"$launch_log"
[[ ${launch_args[*]} == "nvim $test_home/project" ]] || fail "missing packaged Cursor IDE falls back to Neovim"
grep -Fxq "/usr/bin/cursor" "$probe_log" || fail "editor launcher probes Cursor's packaged executable"
[[ ! -e $shim_log ]] || fail "editor launcher never executes a PATH-provided Cursor shim"
pass "Cursor Agent shim cannot be launched as the default graphical editor"
