#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

require_command lua

launch_output=$(OMARCHY_PATH="$ROOT" lua <<'LUA'
package.path = os.getenv("OMARCHY_PATH") .. "/?.lua;" .. package.path
hl = {}
require("default.hypr.helpers")
print(o.launch("foot"))
print(o.launch("[workspace 4 silent] foot"))
print(o.launch("[float] kitty --class notes"))
LUA
) || fail "o.launch can be evaluated"

expected=$'uwsm-app -- foot\n[workspace 4 silent] uwsm-app -- foot\n[float] uwsm-app -- kitty --class notes'
[[ $launch_output == "$expected" ]] || fail "o.launch keeps Hyprland exec-rule brackets outside uwsm-app" "$launch_output"
pass "o.launch keeps Hyprland exec-rule brackets outside uwsm-app"
