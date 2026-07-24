#!/bin/bash

source "$(dirname "${BASH_SOURCE[0]}")/base-test.sh"

require_command lua

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

grep -F 'hl.dsp.exec_cmd("wtype -M " .. modifier .. " -k " .. key:lower() .. " -m " .. modifier)' "$ROOT/default/hypr/bindings/clipboard.lua" >/dev/null ||
  fail "universal clipboard shortcuts use the virtual keyboard"
pass "universal clipboard shortcuts reach focused layer-shell fields"

if grep -F 'hl.dsp.send_key_state' "$ROOT/default/hypr/bindings/clipboard.lua" >/dev/null; then
  fail "universal clipboard shortcuts do not target only normal windows"
fi
pass "universal clipboard shortcuts do not exclude layer-shell fields"

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
