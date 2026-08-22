#!/bin/bash

source "$(dirname "${BASH_SOURCE[0]}")/base-test.sh"

require_command lua

write_mode() {
  local home="$1"
  local mode="$2"
  mkdir -p "$home/.local/state/omarchy/ultimate"
  printf '%s\n' "$mode" >"$home/.local/state/omarchy/ultimate/mode"
}

run_application_bindings() {
  local home="$1"
  local prelude="${2:-}"

  HOME="$home" XDG_CONFIG_HOME="$home/.config" XDG_STATE_HOME="$home/.local/state" OMARCHY_PATH="$ROOT" OMARCHY_BINDING_PRELUDE="$prelude" lua <<'LUA'
package.path = os.getenv("HOME") .. "/.config/?.lua;" .. os.getenv("OMARCHY_PATH") .. "/?.lua;" .. package.path

local prelude = os.getenv("OMARCHY_BINDING_PRELUDE") or ""
if prelude ~= "" then
  assert(load(prelude))()
end

hl = {
  dsp = {
    exec_cmd = function(command)
      return { kind = "exec", arg = command }
    end,
  },
  bind = function(keys, dispatcher, opts)
    opts = opts or {}
    if opts.description then
      print(keys .. "\t" .. opts.description)
    end
  end,
}

require("default.hypr.helpers")
require("default.hypr.bindings.applications")
LUA
}

run_omarchy_bindings() {
  local home="$1"
  local prelude="${2:-}"

  HOME="$home" XDG_CONFIG_HOME="$home/.config" XDG_STATE_HOME="$home/.local/state" OMARCHY_PATH="$ROOT" OMARCHY_BINDING_PRELUDE="$prelude" lua <<'LUA'
package.path = os.getenv("HOME") .. "/.config/?.lua;" .. os.getenv("OMARCHY_PATH") .. "/?.lua;" .. package.path

local function proxy()
  return setmetatable({}, {
    __index = function(self, key)
      local value = proxy()
      rawset(self, key, value)
      return value
    end,
    __call = function()
      return {}
    end,
  })
end

local prelude = os.getenv("OMARCHY_BINDING_PRELUDE") or ""
if prelude ~= "" then
  assert(load(prelude))()
end

hl = setmetatable({
  dsp = proxy(),
  bind = function(keys, dispatcher, opts)
    opts = opts or {}
    if opts.description then
      print(keys .. "\t" .. opts.description)
    end
  end,
  config = function() end,
  env = function() end,
  monitor = function() end,
  window_rule = function() end,
  workspace_rule = function() end,
  layer_rule = function() end,
  gesture = function() end,
  animation = function() end,
  curve = function() end,
  exec_cmd = function() end,
  dispatch = function() end,
  on = function() end,
  timer = function() end,
  get_config = function() return nil end,
  get_active_window = function() return nil end,
}, {
  __index = function()
    return function()
      return {}
    end
  end,
})

require("default.hypr.omarchy")
LUA
}

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

fresh_home="$tmpdir/fresh-home"
mkdir -p "$fresh_home"
fresh_output=$(run_application_bindings "$fresh_home")
grep -Fq $'SUPER + RETURN	Terminal' <<<"$fresh_output" || fail "default application bindings include essentials"
grep -Fq $'SUPER + SHIFT + A	ChatGPT' <<<"$fresh_output" || fail "default application bindings include preinstalled web apps"
pass "default application bindings load from package defaults"

grep -F 'hl.dsp.send_key_state({ mods = mods, key = key, state = "down" })' "$ROOT/default/hypr/bindings/clipboard.lua" >/dev/null ||
  fail "universal clipboard shortcuts send explicit mods to the focused surface"
pass "universal clipboard shortcuts send explicit mods to the focused surface"

if grep -E 'send_key_state\(\{[^}]*window' "$ROOT/default/hypr/bindings/clipboard.lua" >/dev/null; then
  fail "universal clipboard shortcuts do not target only normal windows"
fi
pass "universal clipboard shortcuts do not exclude layer-shell fields"

if grep -F 'wtype -M' "$ROOT/default/hypr/bindings/clipboard.lua" >/dev/null; then
  fail "universal clipboard shortcuts avoid the virtual keyboard so held SUPER cannot merge in"
fi
pass "universal clipboard shortcuts avoid virtual keyboard modifier merging"

removed_home="$tmpdir/removed-home"
mkdir -p "$removed_home/.local/state/omarchy"
touch "$removed_home/.local/state/omarchy/preinstalls-removed"
removed_output=$(run_application_bindings "$removed_home")
grep -Fq $'SUPER + RETURN	Terminal' <<<"$removed_output" || fail "preinstall removal keeps essential bindings"
if grep -Fq $'SUPER + SHIFT + A	ChatGPT' <<<"$removed_output"; then
  fail "preinstall removal skips preinstalled web app bindings"
fi
pass "preinstall removal flag skips optional application bindings"

variable_home="$tmpdir/variable-home"
mkdir -p "$variable_home"
variable_output=$(run_application_bindings "$variable_home" 'omarchy_preinstalled_bindings = false')
grep -Fq $'SUPER + RETURN	Terminal' <<<"$variable_output" || fail "preinstalled binding variable keeps essential bindings"
if grep -Fq $'SUPER + SHIFT + A	ChatGPT' <<<"$variable_output"; then
  fail "preinstalled binding variable skips optional application bindings"
fi
pass "preinstalled binding variable skips optional application bindings"

no_bindings_home="$tmpdir/no-bindings-home"
mkdir -p "$no_bindings_home"
no_bindings_output=$(run_omarchy_bindings "$no_bindings_home" 'omarchy_default_bindings = false')
[[ -z $no_bindings_output ]] || fail "default binding variable disables all Omarchy bindings" "$no_bindings_output"
pass "default binding variable disables all Omarchy bindings"

voxtype_home="$tmpdir/voxtype-home"
voxtype_bin="$tmpdir/voxtype-bin"
mkdir -p "$voxtype_home" "$voxtype_bin"
touch "$voxtype_bin/voxtype"
chmod +x "$voxtype_bin/voxtype"
voxtype_output=$(PATH="$voxtype_bin:$PATH" run_omarchy_bindings "$voxtype_home")
grep -Fq $'SUPER + CTRL + X	Toggle dictation' <<<"$voxtype_output" ||
  fail "installed Voxtype enables its toggle binding"
grep -Fq $'F9	Start dictation (push-to-talk)' <<<"$voxtype_output" ||
  fail "installed Voxtype enables its push-to-talk binding"
grep -Fq $'F9	Stop dictation (push-to-talk)' <<<"$voxtype_output" ||
  fail "installed Voxtype enables its release binding"
pass "installed Voxtype conditionally enables dictation bindings"

voxtype_without_execute_output=$(PATH="$voxtype_bin:$PATH" run_omarchy_bindings \
  "$voxtype_home" 'os.execute = function() return nil, "No child processes", 10 end')
grep -Fq $'SUPER + CTRL + X	Toggle dictation' <<<"$voxtype_without_execute_output" ||
  fail "Voxtype detection does not require spawning a subprocess"
pass "installed Voxtype detection works without os.execute"

missing_bin="$tmpdir/missing-bin"
mkdir -p "$missing_bin"
ln -s "$(command -v lua)" "$missing_bin/lua"
ln -s "$(command -v lspci)" "$missing_bin/lspci"
ln -s "$(command -v sort)" "$missing_bin/sort"
missing_voxtype_output=$(PATH="$missing_bin" run_omarchy_bindings "$voxtype_home")
if grep -Fq $'SUPER + CTRL + X	Toggle dictation' <<<"$missing_voxtype_output"; then
  fail "missing Voxtype skips its bindings"
fi
pass "missing Voxtype skips dictation bindings"

# Desktop Mode is the Ultimate default: Windows keybindings, no Omarchy menu.
desktop_home="$tmpdir/desktop-home"
mkdir -p "$desktop_home"
desktop_err="$tmpdir/desktop-err"
desktop_output=$(run_omarchy_bindings "$desktop_home" 2>"$desktop_err")
if [[ -s $desktop_err ]]; then
  fail "desktop Hyprland config loads" "$(cat "$desktop_err")"
fi
grep -Fq $'SUPER + E	Files' <<<"$desktop_output" || fail "desktop mode binds Win+E to Files"
grep -Fq $'SUPER + UP	Maximize window' <<<"$desktop_output" || fail "desktop mode binds Win+Up to maximize"
grep -Fq $'SUPER + DOWN	Restore or minimize window' <<<"$desktop_output" || fail "desktop mode binds Win+Down to restore or minimize"
grep -Fq $'SUPER + D	Show desktop' <<<"$desktop_output" || fail "desktop mode binds Win+D to Show desktop"
grep -Fq $'SUPER + L	Lock' <<<"$desktop_output" || fail "desktop mode binds Win+L to Lock"
grep -Fq $'SUPER + Super_L	Start' <<<"$desktop_output" || fail "desktop mode binds Super release to Start"
grep -Fq $'ALT + F4	Close window' <<<"$desktop_output" || fail "desktop mode binds Alt+F4 to close"
grep -Fq $'ALT + TAB	Switch windows' <<<"$desktop_output" || fail "desktop mode binds Alt+Tab to the task switcher"
if grep -Fq $'SUPER + SPACE	Omarchy menu' <<<"$desktop_output"; then
  fail "desktop mode does not bind the Omarchy menu to Super+Space"
fi
pass "desktop mode ships the Windows keybinding set"

grep -Fq 'gaps_out = 0' "$ROOT/default/hypr/desktop-windows.lua" || fail "desktop mode zeros gaps_out"
grep -Fq 'plugin load' "$ROOT/default/hypr/desktop-windows.lua" || fail "desktop mode loads hyprbars from an absolute plugin path"
grep -Fq '/usr/lib/hyprland-plugins/hyprbars.so' "$ROOT/default/hypr/desktop-windows.lua" || fail "desktop mode loads hyprbars from /usr/lib/hyprland-plugins"
if grep -Fq '/var/cache/hyprpm/' "$ROOT/default/hypr/desktop-windows.lua"; then
  fail "desktop mode must not load hyprbars from the hyprpm cache"
fi
if grep -Fq 'hyprpm' "$ROOT/default/hypr/desktop-windows.lua"; then
  fail "desktop mode must not reload hyprpm plugins"
fi
grep -Fq 'omarchy-minimize' "$ROOT/default/hypr/desktop-windows.lua" || fail "desktop mode loads omarchy-minimize for in-place hide"
pass "desktop mode compositor chrome is hyprbars, not overlay captions"

# The Grave shortcuts are aliases, so the original SUPER + S pair has to keep
# working alongside them.
scratchpad_home="$tmpdir/scratchpad-home"
mkdir -p "$scratchpad_home"
write_mode "$scratchpad_home" "power-user"
scratchpad_output=$(run_omarchy_bindings "$scratchpad_home")
grep -Fqx $'SUPER + S	Toggle scratchpad' <<<"$scratchpad_output" ||
  fail "scratchpad keeps its existing toggle binding"
grep -Fqx $'SUPER + grave	Toggle scratchpad' <<<"$scratchpad_output" ||
  fail "scratchpad supports a Quake-style toggle binding"
grep -Fqx $'SUPER + ALT + S	Move window to scratchpad' <<<"$scratchpad_output" ||
  fail "scratchpad keeps its existing move binding"
grep -Fqx $'SUPER + SHIFT + grave	Move window to scratchpad' <<<"$scratchpad_output" ||
  fail "scratchpad supports a Quake-style move binding"
pass "scratchpad retains existing bindings and adds Grave shortcuts"

power_home="$tmpdir/power-user-home"
mkdir -p "$power_home"
write_mode "$power_home" "power-user"
power_output=$(run_omarchy_bindings "$power_home")
grep -Fq $'SUPER + SPACE	Omarchy menu' <<<"$power_output" || fail "power-user mode keeps the Omarchy menu binding"
if grep -Fq $'SUPER + Super_L	Start' <<<"$power_output"; then
  fail "power-user mode does not bind Super release to Start"
fi
pass "power-user mode keeps Omarchy Super-key bindings"

# The panel hotkeys claim a row of keys that workspace switching already uses
# under other modifiers, so the count matters as much as the bindings: a tenth
# claim on SUPER + CTRL + a number is a collision with one of these.
panels_home="$tmpdir/panels-home"
mkdir -p "$panels_home"
write_mode "$panels_home" "power-user"
panels_output=$(run_omarchy_bindings "$panels_home")
for panel in 1 2 3 4 5 6 7 8 9; do
  grep -Fqx "SUPER + CTRL + code:$((panel + 9))"$'\t'"Bar panel $panel" <<<"$panels_output" ||
    fail "bar panel hotkeys count the right section" "$panel"
done
number_claims=$(cut -f1 <<<"$panels_output" | grep -cE '^SUPER \+ CTRL \+ code:1[0-9]$' || true)
(( number_claims == 9 )) ||
  fail "only the bar panel hotkeys bind SUPER + CTRL + a number" "$number_claims"
pass "bar panel hotkeys bind SUPER + CTRL + a number without a collision"

migration=$(grep -rl 'Move stock Hyprland user overrides into package defaults' "$ROOT/migrations" | head -n 1 || true)
[[ -n $migration ]] || fail "Hyprland default config migration exists"

migration_home="$tmpdir/migration-home"
mkdir -p "$migration_home/.config/hypr"
cat >"$migration_home/.config/hypr/bindings.lua" <<'LUA'
require("default.hypr.bindings.media")
require("default.hypr.bindings.clipboard")
require("default.hypr.bindings.tiling")
require("default.hypr.bindings.utilities")

-- Application bindings without Omarchy's preinstalled web apps, TUIs, or desktop apps.
o.bind("SUPER + RETURN", "Terminal", { omarchy = "terminal" })
o.bind("SUPER + SHIFT + RETURN", "Browser", { omarchy = "browser" })
o.bind("SUPER + SHIFT + F", "File manager", { omarchy = "nautilus" })
o.bind("SUPER + ALT + SHIFT + F", "File manager (cwd)", { omarchy = "nautilus-cwd" })
o.bind("SUPER + SHIFT + B", "Browser", { omarchy = "browser" })
o.bind("SUPER + SHIFT + ALT + B", "Browser (private)", { omarchy = "browser --private" })
o.bind("SUPER + SHIFT + N", "Editor", { omarchy = "editor" })
LUA
HOME="$migration_home" OMARCHY_PATH="$ROOT" bash -euo pipefail "$migration" >/dev/null
cmp -s "$ROOT/config/hypr/bindings.lua" "$migration_home/.config/hypr/bindings.lua" ||
  fail "plain legacy bindings migrate to the user override stub"
[[ -f $migration_home/.local/state/omarchy/preinstalls-removed ]] ||
  fail "plain legacy bindings preserve preinstall removal state"
pass "migration converts plain legacy bindings to package-owned defaults"

upgrade_script="$ROOT/bin/omarchy-upgrade-to-quattro"
grep -Fq 'touch "$state_dir/preinstalls-removed"' "$upgrade_script" ||
  fail "upgrade-to-quattro preserves preinstall removal state"

mark_line=$(awk '/^mark_removed_preinstalls_from_legacy_bindings$/ { print NR; exit }' "$upgrade_script")
copy_line=$(awk '/^copy_always_config_defaults$/ { print NR; exit }' "$upgrade_script")
[[ -n $mark_line && -n $copy_line ]] || fail "upgrade-to-quattro preinstall marker and config refresh calls exist"
(( mark_line < copy_line )) || fail "upgrade-to-quattro detects plain legacy bindings before overwriting Hyprland bindings"
pass "upgrade-to-quattro preserves preinstall removal before refreshing Hyprland bindings"
