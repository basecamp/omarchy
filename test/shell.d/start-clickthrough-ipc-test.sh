#!/bin/bash

# IPC Start lifecycle on the live compositor. This does not prove click-through;
# that still needs an absolute pointer. It does prove the card maps at 440x560
# and that hide / toggle / dismissOutside unmap it without a fullscreen sink.

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

require_compositor "Start IPC click-through lifecycle"
require_command jq
require_command hyprctl
require_command python3

if ! OMARCHY_PATH="$ROOT" "$ROOT/bin/omarchy-shell" shell ping >/dev/null 2>&1; then
  pass "live omarchy-shell is not answering; skipping Start IPC lifecycle"
  exit 0
fi

shell_ipc() {
  OMARCHY_PATH="$ROOT" "$ROOT/bin/omarchy-shell" "$@"
}

hide_start() {
  shell_ipc shell hide omarchy.ultimate-start >/dev/null 2>&1 || true
}

cleanup() {
  hide_start
}
trap cleanup EXIT

start_layer_json() {
  hyprctl -j layers | python3 -c '
import json, sys
data = json.load(sys.stdin)
out = []
for mon, blob in data.items():
  levels = blob.get("levels", blob) if isinstance(blob, dict) else {}
  if isinstance(levels, dict):
    items = []
    for _level, layers in levels.items():
      items.extend(layers or [])
  else:
    items = levels or []
  for layer in items:
    if not isinstance(layer, dict):
      continue
    if str(layer.get("namespace") or "") == "omarchy-start":
      out.append({"mon": mon, "x": layer.get("x"), "y": layer.get("y"), "w": layer.get("w"), "h": layer.get("h")})
print(json.dumps(out))
'
}

wait_start() {
  local want=$1
  local i
  for i in $(seq 1 20); do
    local json
    json=$(start_layer_json)
    if [[ $want == mapped ]]; then
      jq -e 'length == 1 and .[0].w == 440 and .[0].h == 560' <<<"$json" >/dev/null && return 0
    else
      jq -e 'length == 0' <<<"$json" >/dev/null && return 0
    fi
    sleep 0.1
  done
  return 1
}

hide_start
wait_start unmapped || fail "Start is unmapped before IPC proof"

shell_ipc shell summon omarchy.ultimate-start '{}' >/dev/null
wait_start mapped || {
  printf 'layers: %s\n' "$(start_layer_json)" >&2
  fail "Start summons a 440x560 omarchy-start card"
}
pass "Start summons a 440x560 omarchy-start card"

mapped=$(start_layer_json)
jq -e '.[0].x == 8 and .[0].y == 472' <<<"$mapped" >/dev/null \
  || fail "Start card sits at 8,472 above the Superbar" "got $mapped"
pass "Start card sits at 8,472 above the Superbar"

shell_ipc shell hide omarchy.ultimate-start >/dev/null
wait_start unmapped || fail "Start hide unmaps omarchy-start"
pass "Start hide unmaps omarchy-start"

shell_ipc shell toggle omarchy.ultimate-start '{}' >/dev/null
wait_start mapped || fail "Start toggle maps the card"
shell_ipc shell toggle omarchy.ultimate-start '{}' >/dev/null
wait_start unmapped || fail "Start toggle unmaps the card"
pass "Start toggle maps and unmaps"

shell_ipc shell summon omarchy.ultimate-start '{}' >/dev/null
wait_start mapped || fail "Start remapped before dismissOutside"
shell_ipc shell dismissOutside >/dev/null
wait_start unmapped || fail "dismissOutside unmaps Start"
pass "dismissOutside unmaps Start"
