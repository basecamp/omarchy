#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

require_command lua

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

stub_dir="$tmpdir/bin"
home_dir="$tmpdir/home"
xdg_decoy="$tmpdir/xdg-decoy"
log_file="$tmpdir/hyprctl.log"
marker="$tmpdir/marker"
mkdir -p "$stub_dir" "$home_dir" "$xdg_decoy"

state_dir="$home_dir/.local/state/omarchy/toggles/hypr"
name_file="$state_dir/touchpad-disabled-name"
state_lua="$state_dir/touchpad-disabled.lua"

cat >"$stub_dir/hyprctl" <<'EOF'
#!/bin/bash
case $1 in
  eval) printf '%s\n' "$2" >>"$HYPRCTL_LOG" ;;
  reload) printf 'reload\n' >>"$HYPRCTL_LOG" ;;
esac
EOF
chmod +x "$stub_dir/hyprctl"

cat >"$stub_dir/omarchy-osd" <<'EOF'
#!/bin/bash
:
EOF
chmod +x "$stub_dir/omarchy-osd"

stub_device() {
  local kind=$1
  local name=$2
  cat >"$stub_dir/omarchy-hw-$kind" <<EOF
#!/bin/bash
printf '%s\n' '$name'
EOF
  chmod +x "$stub_dir/omarchy-hw-$kind"
}

# XDG_STATE_HOME deliberately points away from HOME everywhere below: the
# input-device state is hardcoded to ~/.local/state like the sibling toggle
# tools and the pre-migration script, so nothing may read or write the XDG
# directory.
run_toggle() {
  HOME="$home_dir" \
    XDG_STATE_HOME="$xdg_decoy" \
    HYPRCTL_LOG="$log_file" \
    PATH="$stub_dir:$ROOT/bin:$PATH" \
    "$ROOT/bin/omarchy-toggle-input-device" "$@"
}

assert_decoy_untouched() {
  [[ -z $(find "$xdg_decoy" -mindepth 1 -print -quit 2>/dev/null) ]] ||
    fail "input-device state must ignore XDG_STATE_HOME"
}

: >"$log_file"
stub_device touchpad 'elan-touchpad'

run_toggle touchpad off
[[ $(<"$name_file") == "elan-touchpad" ]] || fail "touchpad disable stores the device name as data"
[[ ! -e $state_lua ]] || fail "touchpad disable writes no generated Lua"
grep -Fx 'hl.device({ name = "elan-touchpad", enabled = false })' "$log_file" >/dev/null ||
  fail "touchpad disable applies a quoted Lua device name"
assert_decoy_untouched
pass "touchpad disable persists the device name as data"

: >"$log_file"
run_toggle touchpad on
[[ ! -e $name_file ]] || fail "touchpad enable clears the persisted device name"
grep -Fx 'hl.device({ name = "elan-touchpad", enabled = true })' "$log_file" >/dev/null ||
  fail "touchpad enable applies a quoted Lua device name"
pass "touchpad enable clears persisted disable state"

run_toggle touchpad
[[ -f $name_file ]] || fail "default toggle action disables an enabled touchpad"
run_toggle touchpad
[[ ! -e $name_file ]] || fail "default toggle action enables a disabled touchpad"
pass "default toggle action flips the persisted state"

: >"$log_file"
stub_device touchscreen 'wacom-hid-52eb-finger'
ts_name_file="$state_dir/touchscreen-disabled-name"

run_toggle touchscreen off
[[ $(<"$ts_name_file") == "wacom-hid-52eb-finger" ]] ||
  fail "touchscreen disable stores the device name as data"
grep -Fx 'hl.device({ name = "wacom-hid-52eb-finger", enabled = false })' "$log_file" >/dev/null ||
  fail "touchscreen disable applies a quoted Lua device name"
run_toggle touchscreen on
[[ ! -e $ts_name_file ]] || fail "touchscreen enable clears the persisted device name"
pass "touchscreen routes through the same persisted-name state"

: >"$log_file"
rm -f "$marker"
stub_device touchpad 'touchpad"; touch '"$marker"'; echo "'

run_toggle touchpad off
[[ ! -e $marker ]] || fail "touchpad disable does not execute metacharacters in the device name"
[[ $(<"$name_file") == 'touchpad"; touch '"$marker"'; echo "' ]] ||
  fail "a hostile device name is stored only as data"
[[ ! -e $state_lua ]] || fail "a hostile device name is not written as Lua"
grep -F 'hl.device({ name = "touchpad\"' "$log_file" >/dev/null ||
  fail "hyprctl eval Lua-quotes quotes in the device name" "$(<"$log_file")"
pass "touchpad disable treats USB device names as data"

HOME="$home_dir" XDG_STATE_HOME="$xdg_decoy" OMARCHY_PATH="$ROOT" MARKER="$marker" lua - <<'LUA'
local seen = {}
hl = {
  device = function(opts)
    table.insert(seen, opts)
  end,
}

dofile(os.getenv("OMARCHY_PATH") .. "/default/hypr/bootstrap.lua")
require("default.hypr.toggles")
assert(#seen == 1, "reload disables one device")
assert(seen[1].enabled == false)
assert(seen[1].name == 'touchpad"; touch ' .. os.getenv("MARKER") .. '; echo "', "device name is passed as a string")
LUA
pass "Hyprland reload loads the device name as a string"

# Public PoC device name: USB iProduct is interpolated into hl.device({ name = "..." }).
# os.execute is stubbed so the string is only checked as data.
poc_name='trackpad"})os.execute("~/calc&")--'
stub_device touchpad "$poc_name"

run_toggle touchpad on
: >"$log_file"
run_toggle touchpad off
[[ $(<"$name_file") == "$poc_name" ]] || fail "PoC device name is stored only as data"
[[ ! -e $state_lua ]] || fail "PoC device name is not written as Lua"

HOME="$home_dir" XDG_STATE_HOME="$xdg_decoy" OMARCHY_PATH="$ROOT" \
  POC_NAME="$poc_name" EVAL_SNIPPET="$(<"$log_file")" lua - <<'LUA'
local poc = os.getenv("POC_NAME")
local snippet = os.getenv("EVAL_SNIPPET")
local seen, executed = {}, false

hl = {
  device = function(opts)
    table.insert(seen, opts)
  end,
}
os.execute = function()
  executed = true
end

assert(load(snippet, "eval", "t"))()
assert(executed == false, "quoted hyprctl eval must not run os.execute")
assert(#seen == 1)
assert(seen[1].name == poc)
assert(seen[1].enabled == false)

seen, executed = {}, false
assert(load('hl.device({ name = "' .. poc .. '", enabled = false })', "unquoted", "t"))()
assert(executed == true, "unquoted interpolation is the Lua injection")

seen, executed = {}, false
dofile(os.getenv("OMARCHY_PATH") .. "/default/hypr/bootstrap.lua")
require("default.hypr.toggles")
assert(executed == false, "reload must not run os.execute")
assert(#seen == 1)
assert(seen[1].name == poc)
LUA
pass "PoC device name cannot execute via eval or reload"

cat >"$stub_dir/omarchy-hw-touchpad" <<'EOF'
#!/bin/bash
printf 'evil\nname\n'
EOF
chmod +x "$stub_dir/omarchy-hw-touchpad"

rm -f "$name_file"
set +e
run_toggle touchpad off >/dev/null 2>&1
status=$?
set -e
(( status != 0 )) || fail "disable rejects a device name with a newline"
[[ ! -e $name_file ]] || fail "a rejected device name is not persisted"
pass "disable rejects control characters in a device name"

printf 'elan-touchpad\n' >"$name_file"
set +e
run_toggle touchpad on >/dev/null 2>&1
status=$?
set -e
(( status != 0 )) || fail "enable still reports an invalid device name"
[[ ! -e $name_file ]] || fail "enable clears persisted state even with an invalid device name"
pass "a bad device name cannot wedge the persisted disable"

cat >"$stub_dir/omarchy-hw-touchpad" <<'EOF'
#!/bin/bash
:
EOF
chmod +x "$stub_dir/omarchy-hw-touchpad"

set +e
run_toggle touchpad off >/dev/null 2>&1
status=$?
set -e
(( status != 0 )) || fail "disable errors when no device is found"
[[ ! -e $name_file ]] || fail "no state is written when no device is found"
pass "disable errors when no device is found"

# The migration runs with the same XDG decoy: legacy files were written to
# ~/.local/state, so that is where it must look no matter what XDG says.
run_migration() {
  HOME="$home_dir" XDG_STATE_HOME="$xdg_decoy" HYPRCTL_LOG="$log_file" \
    PATH="$stub_dir:$ROOT/bin:$PATH" \
    bash -euo pipefail "$ROOT/migrations/1787618700.sh" >/dev/null
}

mkdir -p "$state_dir"
rm -f "$state_dir"/*-disabled-name
printf 'hl.device({ name = "synps/2-synaptics-touchpad", enabled = false })\n' >"$state_lua"
printf 'hl.device({ name = "hostile\\"")", enabled = false })\n' >"$state_dir/touchscreen-disabled.lua"

: >"$log_file"
run_migration
[[ $(<"$name_file") == "synps/2-synaptics-touchpad" ]] ||
  fail "migration recovers a device name containing a slash"
[[ ! -e $state_lua ]] || fail "migration deletes the generated touchpad Lua"
[[ ! -e $state_dir/touchscreen-disabled-name ]] ||
  fail "migration does not copy a hostile name out of generated Lua"
[[ ! -e $state_dir/touchscreen-disabled.lua ]] ||
  fail "migration deletes hostile generated Lua even when no name is recovered"
assert_decoy_untouched
# The package hook reloads Hyprland before migrations run, so the disable was
# already dropped for this session; the migration has to put it back.
grep -Fx 'reload' "$log_file" >/dev/null ||
  fail "migration reloads so the recovered disable applies to this session"
pass "migration recovers plain names and discards hostile generated Lua"

printf 'kept-name\n' >"$name_file"
printf 'hl.device({ name = "other-touchpad", enabled = false })\n' >"$state_lua"
run_migration
[[ $(<"$name_file") == "kept-name" ]] || fail "migration keeps an existing device-name file"
[[ ! -e $state_lua ]] || fail "migration still deletes the generated Lua"
pass "migration is idempotent over an existing device-name file"

rm -f "$name_file"
printf 'garbage\n' >"$state_lua"
chmod 000 "$state_lua"
run_migration
[[ ! -e $state_lua ]] || fail "migration removes an unreadable generated Lua"
[[ ! -e $name_file ]] || fail "no name is recovered from an unreadable file"
pass "an unreadable state file does not wedge the migration"

: >"$log_file"
run_migration
[[ ! -s $log_file ]] || fail "migration with nothing to migrate does not reload"
pass "migration no-ops with nothing left to migrate"

# A compromised install carries a leftover generated touchpad-disabled.lua whose
# device name broke out into os.execute. Until the migration deletes it, a reload
# must not source it. toggles.lua excludes those two names from require_all, so the
# payload never runs, while a current name-file disable still applies.
reload_home="$tmpdir/reload-home"
reload_state="$reload_home/.local/state/omarchy/toggles/hypr"
mkdir -p "$reload_state"
reload_marker="$tmpdir/reload-executed"
rm -f "$reload_marker"
printf 'hl.device({ name = "trackpad"})os.execute("touch %s")--", enabled = false })\n' "$reload_marker" \
  >"$reload_state/touchpad-disabled.lua"
printf 'elan-touchpad\n' >"$reload_state/touchpad-disabled-name"

HOME="$reload_home" XDG_STATE_HOME="$reload_home/.local/state" OMARCHY_PATH="$ROOT" lua - <<'LUA'
local disabled = {}
hl = { device = function(opts) table.insert(disabled, opts) end }
dofile(os.getenv("OMARCHY_PATH") .. "/default/hypr/bootstrap.lua")
require("default.hypr.toggles")
assert(#disabled == 1, "only the current name-file disable is applied")
assert(disabled[1].name == "elan-touchpad", "disable uses the stored device name")
assert(disabled[1].enabled == false)
LUA
[[ ! -e $reload_marker ]] || fail "a leftover legacy generated toggle Lua must not execute on reload"
pass "reload excludes leftover legacy toggle Lua while applying the data disable"
