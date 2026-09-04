#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

mock_bin="$test_tmp/bin"
mkdir -p "$mock_bin"

cat >"$mock_bin/hyprctl" <<'SH'
#!/bin/bash
case $1 in
  activeworkspace) printf '{"id":%s}\n' "$OMARCHY_TEST_WORKSPACE" ;;
  clients) printf '%s\n' "$OMARCHY_TEST_CLIENTS" ;;
  dispatch) printf '%s\n' "$2" >"$OMARCHY_TEST_DISPATCH_LOG" ;;
esac
SH
cat >"$mock_bin/setsid" <<'SH'
#!/bin/bash
printf '%s\n' "$*" >"$OMARCHY_TEST_LAUNCH_LOG"
SH
chmod +x "$mock_bin"/*

dispatch_log="$test_tmp/dispatch"
launch_log="$test_tmp/launch"
clients='[
  {"address":"0xone","class":"org.omarchy.btop","title":"foot","workspace":{"id":1}},
  {"address":"0xtwo","class":"org.omarchy.btop","title":"foot","workspace":{"id":2}}
]'

PATH="$mock_bin:$PATH" OMARCHY_TEST_WORKSPACE=2 OMARCHY_TEST_CLIENTS="$clients" \
  OMARCHY_TEST_DISPATCH_LOG="$dispatch_log" OMARCHY_TEST_LAUNCH_LOG="$launch_log" \
  bash "$ROOT/bin/omarchy-launch-or-focus" --current-workspace org.omarchy.btop 'example --flag'

grep -Fq 'address:0xtwo' "$dispatch_log" ||
  fail "workspace-scoped launch focuses the matching window on the current workspace"
[[ ! -e $launch_log ]] || fail "workspace-scoped launch does not open a duplicate on the current workspace"
pass "workspace-scoped launch focuses the matching window on the current workspace"

rm -f "$dispatch_log"
clients='[
  {"address":"0xone","class":"org.omarchy.btop","title":"foot","workspace":{"id":1}}
]'

PATH="$mock_bin:$PATH" OMARCHY_TEST_WORKSPACE=2 OMARCHY_TEST_CLIENTS="$clients" \
  OMARCHY_TEST_DISPATCH_LOG="$dispatch_log" OMARCHY_TEST_LAUNCH_LOG="$launch_log" \
  bash "$ROOT/bin/omarchy-launch-or-focus" --current-workspace org.omarchy.btop 'example --flag'

grep -Fxq 'example --flag' "$launch_log" ||
  fail "workspace-scoped launch opens a window when the match is on another workspace"
[[ ! -e $dispatch_log ]] || fail "workspace-scoped launch ignores matches on another workspace"
pass "workspace-scoped launch opens a window when the match is on another workspace"

rm -f "$launch_log"
PATH="$mock_bin:$PATH" OMARCHY_TEST_WORKSPACE=2 OMARCHY_TEST_CLIENTS="$clients" \
  OMARCHY_TEST_DISPATCH_LOG="$dispatch_log" OMARCHY_TEST_LAUNCH_LOG="$launch_log" \
  bash "$ROOT/bin/omarchy-launch-or-focus" org.omarchy.btop 'example --flag'

grep -Fq 'address:0xone' "$dispatch_log" || fail "unscoped launch still focuses a match on another workspace"
[[ ! -e $launch_log ]] || fail "unscoped launch keeps its global singleton behavior"
pass "unscoped launch keeps its global singleton behavior"

cat >"$mock_bin/omarchy-launch-or-focus" <<'SH'
#!/bin/bash
printf '%s\n' "$@" >"$OMARCHY_TEST_FORWARD_LOG"
SH
chmod +x "$mock_bin/omarchy-launch-or-focus"

forward_log="$test_tmp/forward"
PATH="$mock_bin:$PATH" OMARCHY_TEST_FORWARD_LOG="$forward_log" \
  bash "$ROOT/bin/omarchy-launch-or-focus-tui" --current-workspace btop

mapfile -t forwarded <"$forward_log"
[[ ${forwarded[0]} == "--current-workspace" ]] || fail "TUI launcher forwards the workspace scope"
[[ ${forwarded[1]} == "org.omarchy.btop" ]] || fail "TUI launcher derives the btop app id"
[[ ${forwarded[2]} == "omarchy-launch-tui btop" ]] || fail "TUI launcher preserves its launch command"
pass "TUI launcher forwards the workspace scope"
