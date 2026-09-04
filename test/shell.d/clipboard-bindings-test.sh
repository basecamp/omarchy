#!/bin/bash

source "$(dirname "${BASH_SOURCE[0]}")/base-test.sh"

require_command lua

chord_for() {
  local keys="$1" class="${2:-}"

  OMARCHY_PATH="$ROOT" OMARCHY_TEST_KEYS="$keys" OMARCHY_TEST_CLASS="$class" lua <<'LUA'
package.path = os.getenv("OMARCHY_PATH") .. "/?.lua;" .. package.path

local bindings = {}
local sent = {}

hl = {
  dsp = {
    send_key_state = function(spec)
      return spec
    end,
    exec_cmd = function(command)
      return { kind = "exec", arg = command }
    end,
  },
  bind = function(keys, dispatcher)
    bindings[keys] = dispatcher
  end,
  dispatch = function(spec)
    if type(spec) == "table" and spec.state == "down" then
      sent[#sent + 1] = spec.mods .. " " .. spec.key
    elseif type(spec) == "table" and spec.kind == "exec" then
      sent[#sent + 1] = "EXEC " .. spec.arg
    end
  end,
  timer = function() end,
  get_active_window = function()
    local class = os.getenv("OMARCHY_TEST_CLASS")
    if class == nil or class == "" then
      return nil
    end

    local terminal = class == "kitty" or class == "com.mitchellh.ghostty" or
      class == "foot" or class == "Alacritty" or class:match("^org%.omarchy%.") or
      class:match("^TUI%.")
    return { address = "0xabc123", class = class, pid = 1234, stable_id = 5678, tags = terminal and { "terminal*" } or {} }
  end,
}

require("default.hypr.helpers")
o.shell_succeeds = function() error("clipboard inspection must not block Hyprland") end
require("default.hypr.bindings.clipboard")

local dispatcher = bindings[os.getenv("OMARCHY_TEST_KEYS")]
assert(type(dispatcher) == "function", "no callback bound")
dispatcher()
print(sent[1] or "")
LUA
}

assert_chord() {
  local keys="$1" class="$2" expected="$3" description="$4"
  local actual

  actual=$(chord_for "$keys" "$class")
  [[ $actual == "$expected" ]] || fail "$description" "expected: $expected
actual:   $actual"
  pass "$description"
}

terminal_command="EXEC omarchy-clipboard-paste-terminal 1234 5678 '0xabc123'"
assert_chord "SUPER + V" "com.mitchellh.ghostty" "$terminal_command" "Ghostty paste inspects the clipboard outside Hyprland"
assert_chord "SUPER + V" "kitty" "$terminal_command" "Kitty paste inspects the clipboard outside Hyprland"
assert_chord "SUPER + V" "foot" "$terminal_command" "Foot paste remains targeted to its original window"
assert_chord "SUPER + V" "Alacritty" "$terminal_command" "Alacritty paste remains targeted to its original window"
assert_chord "SUPER + V" "org.omarchy.agent" "$terminal_command" "Omarchy TUIs inspect their underlying terminal"
assert_chord "SUPER + V" "google-chrome" "CTRL V" "GUI paste uses Ctrl+V"
assert_chord "SUPER + C" "org.omarchy.btop" "CTRL Insert" "copy keeps the terminal chord in Omarchy TUIs"

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT
mkdir -p "$tmpdir/bin"

cat >"$tmpdir/bin/wl-paste" <<'SH'
#!/bin/bash
printf '%b' "$WL_PASTE_TYPES"
SH

cat >"$tmpdir/bin/readlink" <<'SH'
#!/bin/bash
[[ $# == 1 && $1 == "/proc/1234/exe" ]] || exit 1
printf '/usr/bin/%s\n' "$TERMINAL_EXE"
SH

cat >"$tmpdir/bin/hyprctl" <<'SH'
#!/bin/bash
[[ $# == 2 && $1 == "eval" ]] || exit 1
printf '%s\n' "$2" >"$HYPRCTL_OUT"
SH

chmod +x "$tmpdir/bin/wl-paste" "$tmpdir/bin/readlink" "$tmpdir/bin/hyprctl"

TERMINAL_EXE=ghostty WL_PASTE_TYPES='image/png\n' HYPRCTL_OUT="$tmpdir/hyprctl" PATH="$tmpdir/bin:$PATH" \
  "$ROOT/bin/omarchy-clipboard-paste-terminal" 1234 5678 0xabc123
grep -Fq 'local mods, key = "CTRL", "V"' "$tmpdir/hyprctl" || fail "terminal image paste sends Ctrl+V"
pass "terminal image paste sends Ctrl+V"

rm -f "$tmpdir/hyprctl"
TERMINAL_EXE='ghostty (deleted)' WL_PASTE_TYPES='image/png\n' HYPRCTL_OUT="$tmpdir/hyprctl" PATH="$tmpdir/bin:$PATH" \
  "$ROOT/bin/omarchy-clipboard-paste-terminal" 1234 5678 0xabc123
grep -Fq 'local mods, key = "CTRL", "V"' "$tmpdir/hyprctl" || fail "terminal image paste recognizes an upgraded Ghostty process"
pass "terminal image paste recognizes an upgraded Ghostty process"

rm -f "$tmpdir/hyprctl"
TERMINAL_EXE=kitty WL_PASTE_TYPES='text/plain\n' HYPRCTL_OUT="$tmpdir/hyprctl" PATH="$tmpdir/bin:$PATH" \
  "$ROOT/bin/omarchy-clipboard-paste-terminal" 1234 5678 0xabc123
grep -Fq 'local mods, key = "SHIFT", "Insert"' "$tmpdir/hyprctl" || fail "terminal text paste sends Shift+Insert"
pass "terminal text paste sends Shift+Insert"

rm -f "$tmpdir/hyprctl"
TERMINAL_EXE=foot WL_PASTE_TYPES='image/png\n' HYPRCTL_OUT="$tmpdir/hyprctl" PATH="$tmpdir/bin:$PATH" \
  "$ROOT/bin/omarchy-clipboard-paste-terminal" 1234 5678 0xabc123
grep -Fq 'local mods, key = "SHIFT", "Insert"' "$tmpdir/hyprctl" || fail "Foot image paste keeps Shift+Insert"
pass "Foot image paste keeps Shift+Insert"

rm -f "$tmpdir/hyprctl"
TERMINAL_EXE=ghostty WL_PASTE_TYPES='text/plain\nimage/png\n' HYPRCTL_OUT="$tmpdir/hyprctl" PATH="$tmpdir/bin:$PATH" \
  "$ROOT/bin/omarchy-clipboard-paste-terminal" 1234 5678 0xabc123
grep -Fq 'local mods, key = "CTRL", "V"' "$tmpdir/hyprctl" || fail "terminal image paste takes precedence for mixed clipboard data"
pass "terminal image paste takes precedence for mixed clipboard data"

grep -Fq 'state = "down"' "$tmpdir/hyprctl" || fail "terminal paste presses the synthetic shortcut"
grep -Fq 'state = "up"' "$tmpdir/hyprctl" || fail "terminal paste releases the synthetic shortcut"
pass "terminal paste presses and releases the synthetic shortcut"

grep -Fq 'window.pid == 1234 and window.stable_id == 5678' "$tmpdir/hyprctl" || fail "terminal paste revalidates the original window"
grep -Fq 'hl.get_window("address:0xabc123")' "$tmpdir/hyprctl" || fail "terminal paste targets the original window"
pass "terminal paste targets the original window"
