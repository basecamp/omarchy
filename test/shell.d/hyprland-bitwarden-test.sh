#!/bin/bash

set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/base-test.sh"

require_command lua

# "lua -" rather than "lua": reading the chunk off bare stdin, Lua 5.5 reports the
# error and still exits 0, so every assertion below would be dead.
OMARCHY_PATH="$ROOT" lua - <<'LUA'
package.path = os.getenv("OMARCHY_PATH") .. "/?.lua;" .. package.path

local rules = {}
hl = {
  window_rule = function(rule)
    table.insert(rules, rule)
  end,
}

require("default.hypr.helpers")
require("default.hypr.apps.bitwarden")

assert(#rules == 2, "Bitwarden defines desktop and browser-extension rules")

local desktop = rules[1]
assert(desktop.match.class == "^(Bitwarden)$", "desktop rule keeps its exact class match")
assert(desktop.no_screen_share == true, "desktop rule blocks screen sharing")

local extension = rules[2]
assert(extension.match.class == ".*nngceckbapebfimnlniiiahkandclblb.*", "extension rule matches every Chromium browser prefix and popup suffix")
assert(extension.float == true, "extension popouts float directly")
assert(extension.no_blur == true, "extension popouts disable blur")
assert(extension.no_screen_share == true, "extension popouts block screen sharing")
assert(type(extension.max_size) == "table", "extension maximum size uses a vec2")
assert(extension.max_size[1] == 480 and extension.max_size[2] == 650, "extension popouts stay within Bitwarden's supported size")
assert(extension.tag == nil, "extension popouts bypass the generic floating-window size")
LUA

pass "Bitwarden popouts match all Chromium browsers at their supported size"
