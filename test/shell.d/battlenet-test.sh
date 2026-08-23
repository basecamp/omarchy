#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

require_command lua

install_script="$ROOT/bin/omarchy-install-gaming-battlenet"

[[ ! -f $ROOT/applications/battlenet.desktop ]] || fail "Battle.net launcher is not part of default application refresh"
[[ -f $ROOT/default/applications/battlenet.desktop ]] || fail "Battle.net launcher template is available to the installer"
grep -F '$OMARCHY_PATH/default/applications/battlenet.desktop' "$install_script" >/dev/null ||
  fail "Battle.net installer installs the launcher from the installer-only template"

pass "Battle.net launcher is only installed by the Battle.net installer"

wow_rule=$(OMARCHY_PATH="$ROOT" lua <<'LUA'
package.path = os.getenv("OMARCHY_PATH") .. "/?.lua;" .. package.path

o = {
  window = function(match, rules)
    if match.title == "^World of Warcraft$" then
      print(match.class)
      print(tostring(match.xwayland))
      print(tostring(rules.focus_on_activate))
      print(rules.suppress_event)
    end
  end,
}

require("default.hypr.apps.battlenet")
LUA
)

expected_wow_rule=$'^steam_app_battlenet$\ntrue\nfalse\nfullscreen maximize'
[[ $wow_rule == "$expected_wow_rule" ]] || fail "WoW keeps compositor fullscreen without stealing focus" "$wow_rule"

pass "WoW keeps compositor fullscreen without stealing focus"
