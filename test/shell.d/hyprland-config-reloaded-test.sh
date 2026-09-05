#!/bin/bash

set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/base-test.sh"

require_command lua
require_command sha256sum

command_path="$ROOT/bin/omarchy-hyprland-config-reloaded"
hooks_lua="$ROOT/default/hypr/hooks.lua"

grep -F '%.lua}' "$command_path" >/dev/null
grep -F 'omarchy-hook hyprland-config "$csv"' "$command_path" >/dev/null
grep -F 'omarchy/hyprland-config' "$command_path" >/dev/null
grep -F 'SNAPSHOT=' "$command_path" >/dev/null
pass "config hook reports changed config files by name"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

stub_bin="$test_tmp/bin"
test_home="$test_tmp/home"
config_dir="$test_home/.config/hypr"
mkdir -p "$stub_bin" "$config_dir"

cat >"$stub_bin/omarchy-hook" <<SH
#!/bin/bash
echo "HOOK CALL: \$*" >>"\$TEST_LOG"
SH
chmod +x "$stub_bin/omarchy-hook"

run_hook() {
  HOME="$test_home" \
  XDG_CONFIG_HOME="$test_home/.config" \
  XDG_STATE_HOME="$test_home/.local/state" \
  PATH="$stub_bin:$ROOT/bin:$PATH" \
  TEST_LOG="$test_tmp/log.txt" \
    "$command_path"
}

for file in bindings.lua looknfeel.lua monitors.lua input.lua autostart.lua hyprland.lua foo.lua; do
  echo "-- $file" >"$config_dir/$file"
done

run_hook
grep -Fx 'HOOK CALL: hyprland-config ' "$test_tmp/log.txt" >/dev/null
pass "first config hook run establishes the baseline with no files"

echo '-- changed' >>"$config_dir/bindings.lua"
echo '-- changed' >>"$config_dir/looknfeel.lua"
run_hook
grep -Fx 'HOOK CALL: hyprland-config bindings,looknfeel' "$test_tmp/log.txt" >/dev/null
pass "config hook reports changed config files in filename order"

run_hook
(( $(grep -c '^HOOK CALL:' "$test_tmp/log.txt") == 3 )) || fail "unchanged reload still fires the hook"
grep -Fx 'HOOK CALL: hyprland-config ' "$test_tmp/log.txt" >/dev/null
pass "unchanged reload fires the hook with no files"

cat >"$test_tmp/hooks-check.lua" <<'LUA_EOF'
package.path = os.getenv("OMARCHY_PATH") .. "/?.lua;" .. package.path

local registered = {}
local exec_cmds = {}
hl = {
  on = function(event, callback)
    registered[event] = callback
  end,
  exec_cmd = function(command)
    exec_cmds[#exec_cmds + 1] = command
  end,
}

require("default.hypr.hooks")

if not registered["config.reloaded"] then
  print("not ok - hooks module registers config.reloaded")
  os.exit(1)
end
print("ok - hooks module registers config.reloaded")

registered["config.reloaded"]()
if exec_cmds[1] ~= "omarchy-hyprland-config-reloaded" then
  print("not ok - config reload fires the hook command")
  os.exit(1)
end
print("ok - config reload fires the hook command")
LUA_EOF
lua_output=$(OMARCHY_PATH="$ROOT" lua "$test_tmp/hooks-check.lua" 2>&1) || fail "hooks module lua check failed" "$lua_output"
grep -q '^ok - hooks module registers config.reloaded$' <<<"$lua_output"
grep -q '^ok - config reload fires the hook command$' <<<"$lua_output"
pass "hooks module registers config.reloaded and fires the hook command"
