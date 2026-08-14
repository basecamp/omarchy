#!/bin/bash

source "$(dirname "$0")/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

mock_bin="$test_tmp/bin"
hyprctl_log="$test_tmp/hyprctl.log"
shell_log="$test_tmp/omarchy-shell.log"
mkdir -p "$mock_bin"

cat >"$mock_bin/hyprctl" <<'SH'
#!/bin/bash
printf '%s\n' "$*" >>"$HYPRCTL_LOG"
SH
chmod +x "$mock_bin/hyprctl"

cat >"$mock_bin/omarchy-shell" <<'SH'
#!/bin/bash
printf '%s\n' "$*" >>"$SHELL_LOG"
if [[ ${OMARCHY_SHELL_RESULT:-} == fail ]]; then
  echo "omarchy-shell is not running" >&2
  exit 1
fi
printf '%s\n' "${OMARCHY_SHELL_RESULT:-none}"
SH
chmod +x "$mock_bin/omarchy-shell"

run_close() {
  : >"$hyprctl_log"
  : >"$shell_log"
  PATH="$mock_bin:$PATH" HYPRCTL_LOG="$hyprctl_log" SHELL_LOG="$shell_log" \
    OMARCHY_SHELL_RESULT="$1" \
    "$ROOT/bin/omarchy-hyprland-window-close"
}

grep -Fq '"omarchy-hyprland-window-close"' "$ROOT/default/hypr/bindings/tiling.lua" ||
  fail "SUPER + W closes through omarchy-hyprland-window-close"
pass "SUPER + W closes through omarchy-hyprland-window-close"

grep -Fq 'OMARCHY_SHELL_IPC_TIMEOUT=0.5s' "$ROOT/bin/omarchy-hyprland-window-close" ||
  fail "close uses a GNU timeout duration the shell IPC wrapper accepts"
pass "close uses a GNU timeout duration the shell IPC wrapper accepts"

run_close hidden
[[ -s $hyprctl_log ]] && fail "hidden panel skip does not dispatch window close"
grep -Fq 'shell hideOpen' "$shell_log" || fail "close asks the shell to hide an open panel"
pass "an open panel is hidden instead of the window"

run_close none
grep -Fq 'dispatch hl.dsp.window.close()' "$hyprctl_log" ||
  fail "no panel falls through to the Lua window close"
pass "no open panel closes the focused window"

run_close fail
grep -Fq 'dispatch hl.dsp.window.close()' "$hyprctl_log" ||
  fail "a missing shell still closes the focused window"
pass "a missing shell still closes the focused window"
