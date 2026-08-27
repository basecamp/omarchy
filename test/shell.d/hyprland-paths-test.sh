#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

require_command lua

run_paths() {
  lua - <<'LUA'
package.path = os.getenv("OMARCHY_PATH") .. "/?.lua;" .. package.path
local paths = require("default.hypr.paths")
assert(paths.config_home == os.getenv("EXPECTED_CONFIG"), "config_home: " .. paths.config_home)
assert(paths.state_home == os.getenv("EXPECTED_STATE"), "state_home: " .. paths.state_home)
LUA
}

HOME="/home/test-user" OMARCHY_PATH="$ROOT" \
  XDG_CONFIG_HOME= XDG_STATE_HOME= \
  EXPECTED_CONFIG="/home/test-user/.config" EXPECTED_STATE="/home/test-user/.local/state" \
  run_paths
pass "empty XDG path variables fall back to their defaults"

HOME="/home/test-user" OMARCHY_PATH="$ROOT" \
  XDG_CONFIG_HOME="/custom/config" XDG_STATE_HOME="/custom/state" \
  EXPECTED_CONFIG="/custom/config" EXPECTED_STATE="/custom/state" \
  run_paths
pass "set XDG path variables are honored"
