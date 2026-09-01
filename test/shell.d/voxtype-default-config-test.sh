#!/bin/bash

source "$(dirname "$0")/base-test.sh"

config="$ROOT/default/voxtype/config.toml"

grep -Fxq 'mode = "paste"' "$config" || fail "Voxtype pastes transcriptions by default"
grep -Fxq 'paste_keys = "super+v"' "$config" || fail "Voxtype uses Omarchy universal paste"

pass "Voxtype default output works across regular and terminal applications"
