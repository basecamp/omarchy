#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

run_node_test <<'JS'
const fs = require('fs')
const utilQml = fs.readFileSync(path.join(root, 'shell/Commons/Util.qml'), 'utf8')

assert(
  utilQml.includes('import Quickshell'),
  'shell launch helper can read Omarchy path'
)
assert(
  utilQml.includes('Quickshell.env("OMARCHY_PATH")'),
  'shell launch helper uses Omarchy path'
)
assert(
  /function hyprExecCommand\(command\)[\s\S]*omarchy-hyprland-launch/.test(utilQml),
  'shell launch helper routes through Hyprland launch command'
)

JS

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

cat >"$tmp_dir/hyprctl" <<'SCRIPT'
#!/bin/bash
case "$1" in
  activeworkspace)
    printf '{"id":2,"name":"2"}\n'
    ;;
  dispatch)
    printf '%s\n' "$2" >>"$TEST_LOG"
    ;;
esac
SCRIPT
chmod +x "$tmp_dir/hyprctl"

cat >"$tmp_dir/jq" <<'SCRIPT'
#!/bin/bash
cat >/dev/null
printf '2\n'
SCRIPT
chmod +x "$tmp_dir/jq"

export TEST_LOG="$tmp_dir/log"
export PATH="$tmp_dir:$ROOT/bin:$PATH"
export HYPRLAND_INSTANCE_SIGNATURE=test

"$ROOT/bin/omarchy-hyprland-launch" "echo hello"

dispatch=$(<"$TEST_LOG")
[[ $dispatch == *'workspace = "2"'* ]] || fail "hyprland launch targets active workspace" "$dispatch"
[[ $dispatch == *'hl.exec_cmd("echo hello"'* ]] || fail "hyprland launch dispatches command" "$dispatch"
pass "hyprland launch targets active workspace"

unset HYPRLAND_INSTANCE_SIGNATURE
"$ROOT/bin/omarchy-hyprland-launch" "printf fallback > $(printf '%q' "$tmp_dir/fallback")"
[[ $(<"$tmp_dir/fallback") == "fallback" ]] || fail "hyprland launch falls back outside Hyprland"
pass "hyprland launch falls back outside Hyprland"
