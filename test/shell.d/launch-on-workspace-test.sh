#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

grep -F 'return "omarchy-launch-on-workspace " .. shell_quote(command)' "$ROOT/default/hypr/helpers.lua" >/dev/null ||
  fail "keybind app launches pin the workspace they were started from"
pass "keybind app launches pin the workspace they were started from"

grep -F 'initial_workspace_tracking = 0' "$ROOT/default/hypr/looknfeel.lua" >/dev/null ||
  fail "global workspace tracking stays off so portal dialogs follow the requesting app"
pass "global workspace tracking stays off so portal dialogs follow the requesting app"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

mock_bin="$test_tmp/bin"
mkdir -p "$mock_bin"

cat >"$mock_bin/hyprctl" <<'SH'
#!/bin/bash

if [[ ${1:-} == "activeworkspace" && ${2:-} == "-j" ]]; then
  if [[ -n ${OMARCHY_TEST_WORKSPACE_JSON:-} ]]; then
    printf '%s\n' "$OMARCHY_TEST_WORKSPACE_JSON"
  else
    printf '%s\n' '{"id":3,"name":"3"}'
  fi
  exit 0
fi

if [[ ${1:-} == "dispatch" && ${2:-} == hl.dsp.exec_cmd* ]]; then
  printf '%s\n' "${2:-}" >>"$OMARCHY_TEST_DISPATCH_LOG"
  if [[ ${OMARCHY_TEST_DISPATCH_STATUS:-0} != 0 ]]; then
    exit "$OMARCHY_TEST_DISPATCH_STATUS"
  fi
  printf 'ok\n'
  exit 0
fi

exit 1
SH

chmod +x "$mock_bin/hyprctl"

export PATH="$mock_bin:$PATH"
export OMARCHY_TEST_DISPATCH_LOG="$test_tmp/dispatch.log"

: >"$OMARCHY_TEST_DISPATCH_LOG"
"$ROOT/bin/omarchy-launch-on-workspace" "uwsm-app -- gtk-launch 'steam.desktop'"
grep -Fqx 'hl.dsp.exec_cmd("uwsm-app -- gtk-launch '\''steam.desktop'\''", { workspace = "3 silent" })' "$OMARCHY_TEST_DISPATCH_LOG" ||
  fail "helper dispatches the command onto the active workspace" "$(<"$OMARCHY_TEST_DISPATCH_LOG")"
pass "helper dispatches the command onto the active workspace"

: >"$OMARCHY_TEST_DISPATCH_LOG"
OMARCHY_TEST_WORKSPACE_JSON='{}' "$ROOT/bin/omarchy-launch-on-workspace" "echo launched" >"$test_tmp/fallback.out"
[[ $(<"$test_tmp/fallback.out") == launched ]] ||
  fail "helper runs the command directly when no workspace id is available" "$(<"$test_tmp/fallback.out")"
[[ ! -s $OMARCHY_TEST_DISPATCH_LOG ]] ||
  fail "helper does not dispatch when no workspace id is available"
pass "helper runs the command directly when no workspace id is available"
