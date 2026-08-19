#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

require_command lua

helper="$ROOT/bin/omarchy-cmd-terminal-paste"
[[ -x $helper ]] || fail "terminal paste helper is executable"
grep -Fqx '# omarchy:hidden=true' "$helper" || fail "terminal paste helper is hidden from command listings"
grep -Fqx '# omarchy:summary=Paste clipboard content into the active terminal' "$helper" ||
  fail "terminal paste helper has command metadata"
pass "terminal paste helper has hidden command metadata"

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

fake_bin="$tmpdir/bin"
mkdir -p "$fake_bin"

cat >"$fake_bin/wl-paste" <<'SH'
#!/bin/bash

printf '%s\n' "$*" >>"$WL_PASTE_LOG"

case "$WL_PASTE_MODE" in
  image)
    printf '%s\n' 'image/png'
    ;;
  mixed-case-image)
    printf '%s\n' 'Image/PNG'
    ;;
  text)
    printf '%s\n' 'text/plain;charset=utf-8'
    ;;
  text-atom)
    printf '%s\n' 'UTF8_STRING'
    ;;
  mixed)
    printf '%s\n' 'image/png' 'text/plain'
    ;;
  mixed-case-text)
    printf '%s\n' 'image/png' 'Text/Plain;Charset=UTF-8'
    ;;
  empty)
    ;;
  unknown)
    printf '%s\n' 'application/octet-stream'
    ;;
  oversized)
    printf '%s\n' 'image/png'
    while :; do
      printf '%s\n' 'application/octet-stream'
    done
    ;;
  failure)
    exit 1
    ;;
  timeout)
    sleep 2
    printf '%s\n' 'image/png'
    ;;
  *)
    exit 2
    ;;
esac
SH
chmod +x "$fake_bin/wl-paste"

cat >"$fake_bin/hyprctl" <<'SH'
#!/bin/bash

printf '%s\n' "$*" >>"$HYPRCTL_LOG"

if [[ ${HYPRCTL_SIGNAL_DOWN:-false} == "true" && $* == *'state = "down"'* ]]; then
  kill -TERM "$PPID"
fi
SH
chmod +x "$fake_bin/hyprctl"

assert_terminal_paste() {
  local mode="$1"
  local expected_mods="$2"
  local expected_key="$3"
  local description="$4"
  local hyprctl_log="$tmpdir/hyprctl-$mode.log"
  local wl_paste_log="$tmpdir/wl-paste-$mode.log"

  : >"$hyprctl_log"
  : >"$wl_paste_log"

  PATH="$fake_bin:$PATH" \
    HYPRCTL_LOG="$hyprctl_log" \
    WL_PASTE_LOG="$wl_paste_log" \
    WL_PASTE_MODE="$mode" \
    "$helper"

  [[ $(<"$wl_paste_log") == "--list-types" ]] ||
    fail "$description queries MIME names only" "$(<"$wl_paste_log")"

  mapfile -t dispatches <"$hyprctl_log"
  (( ${#dispatches[@]} == 2 )) ||
    fail "$description sends one key down and one key up" "$(<"$hyprctl_log")"

  [[ ${dispatches[0]} == "dispatch hl.dsp.send_key_state({ mods = \"$expected_mods\", key = \"$expected_key\", state = \"down\" })" ]] ||
    fail "$description sends the expected key down" "${dispatches[0]}"
  [[ ${dispatches[1]} == "dispatch hl.dsp.send_key_state({ mods = \"$expected_mods\", key = \"$expected_key\", state = \"up\" })" ]] ||
    fail "$description sends the expected key up" "${dispatches[1]}"

  if grep -Fq 'window =' "$hyprctl_log"; then
    fail "$description sends to the focused surface without a window target"
  fi

  pass "$description"
}

assert_terminal_paste image CTRL V "image-only clipboard uses raw Ctrl+V"
assert_terminal_paste mixed-case-image CTRL V "mixed-case image MIME uses raw Ctrl+V"
assert_terminal_paste text SHIFT Insert "text clipboard uses terminal paste"
assert_terminal_paste text-atom SHIFT Insert "standard text atoms use terminal paste"
assert_terminal_paste mixed SHIFT Insert "mixed clipboard uses terminal paste"
assert_terminal_paste mixed-case-text SHIFT Insert "mixed-case text MIME keeps mixed clipboard on terminal paste"
assert_terminal_paste empty SHIFT Insert "empty clipboard falls back to terminal paste"
assert_terminal_paste unknown SHIFT Insert "unknown clipboard falls back to terminal paste"
assert_terminal_paste oversized SHIFT Insert "oversized MIME output falls back to terminal paste"
assert_terminal_paste failure SHIFT Insert "clipboard query failure falls back to terminal paste"
assert_terminal_paste timeout SHIFT Insert "clipboard query timeout falls back to terminal paste"

interrupt_log="$tmpdir/hyprctl-interrupt.log"
: >"$interrupt_log"
set +e
PATH="$fake_bin:$PATH" \
  HYPRCTL_LOG="$interrupt_log" \
  HYPRCTL_SIGNAL_DOWN=true \
  WL_PASTE_LOG="$tmpdir/wl-paste-interrupt.log" \
  WL_PASTE_MODE=image \
  "$helper"
interrupt_status=$?
set -e
(( interrupt_status == 143 )) || fail "interrupted paste reports termination" "$interrupt_status"
mapfile -t interrupt_dispatches <"$interrupt_log"
(( ${#interrupt_dispatches[@]} == 2 )) ||
  fail "interrupted paste releases the synthetic key" "$(<"$interrupt_log")"
[[ ${interrupt_dispatches[1]} == *'state = "up" })' ]] ||
  fail "interrupted paste sends key up during cleanup" "${interrupt_dispatches[1]}"
pass "interrupted paste releases the synthetic key"

run_clipboard_binding() {
  local window_kind="$1"

  OMARCHY_PATH="$ROOT" WINDOW_KIND="$window_kind" lua <<'LUA'
package.path = os.getenv("OMARCHY_PATH") .. "/?.lua;" .. package.path

local paste_handler

o = {
  bind = function(_, description, handler)
    if description == "Universal paste" then
      paste_handler = handler
    end
  end,
}

hl = {
  dsp = {
    exec_cmd = function(command)
      return { kind = "exec", command = command }
    end,
    send_key_state = function(args)
      return { kind = "key", args = args }
    end,
  },
  dispatch = function(dispatcher)
    if dispatcher.kind == "exec" then
      print("exec\t" .. dispatcher.command)
    elseif dispatcher.kind == "key" then
      print(table.concat({ "key", dispatcher.args.mods, dispatcher.args.key, dispatcher.args.state }, "\t"))
    end
  end,
  get_active_window = function()
    if os.getenv("WINDOW_KIND") == "terminal" then
      return { tags = { "terminal*" } }
    end

    return { tags = {} }
  end,
  timer = function(callback)
    callback()
  end,
}

require("default.hypr.bindings.clipboard")
assert(type(paste_handler) == "function")
paste_handler()
LUA
}

terminal_binding_output=$(run_clipboard_binding terminal)
[[ $terminal_binding_output == $'exec\tomarchy-cmd-terminal-paste' ]] ||
  fail "terminal Super+V launches the MIME-aware helper asynchronously" "$terminal_binding_output"
pass "terminal Super+V launches the MIME-aware helper asynchronously"

gui_binding_output=$(run_clipboard_binding gui)
[[ $gui_binding_output == $'key\tCTRL\tV\tdown\nkey\tCTRL\tV\tup' ]] ||
  fail "GUI Super+V keeps explicit Ctrl+V injection" "$gui_binding_output"
pass "GUI Super+V keeps explicit Ctrl+V injection"
