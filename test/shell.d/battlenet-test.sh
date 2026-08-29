#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

require_command lua
require_command jq

install_script="$ROOT/bin/omarchy-install-gaming-battlenet"
launch_script="$ROOT/bin/omarchy-launch-battlenet"
rules_file="$ROOT/default/hypr/apps/battlenet.lua"

[[ ! -f $ROOT/applications/battlenet.desktop ]] || fail "Battle.net launcher is not part of default application refresh"
[[ -f $ROOT/default/applications/battlenet.desktop ]] || fail "Battle.net launcher template is available to the installer"
grep -F '$OMARCHY_PATH/default/applications/battlenet.desktop' "$install_script" >/dev/null ||
  fail "Battle.net installer installs the launcher from the installer-only template"

pass "Battle.net launcher is only installed by the Battle.net installer"

launcher_rule=$(OMARCHY_PATH="$ROOT" lua <<'LUA'
package.path = os.getenv("OMARCHY_PATH") .. "/?.lua;" .. package.path

o = {
  window = function(match, rules)
    if match.title == "^Battle\\.net$" then
      print(match.class)
      print(tostring(rules.tile))
      print(tostring(rules.float))
      print(tostring(rules.size))
      print(rules.suppress_event)
    end
  end,
}

require("default.hypr.apps.battlenet")
LUA
)

expected_launcher_rule=$'^steam_app_battlenet$\ntrue\nnil\nnil\nmaximize x11configurerequest'
[[ $launcher_rule == "$expected_launcher_rule" ]] ||
  fail "Battle.net launcher tiles and ignores X11 configure requests" "$launcher_rule"

pass "Battle.net launcher tiles and ignores X11 configure requests"

setup_rule=$(OMARCHY_PATH="$ROOT" lua <<'LUA'
package.path = os.getenv("OMARCHY_PATH") .. "/?.lua;" .. package.path

o = {
  window = function(match, rules)
    if match.title == "^Battle\\.net Setup$" then
      print(match.class)
      print(tostring(rules.float))
      print(tostring(rules.center))
      print(tostring(rules.decorate))
      print(rules.suppress_event)
    end
  end,
}

require("default.hypr.apps.battlenet")
LUA
)

expected_setup_rule=$'^steam_app_battlenet$\ntrue\ntrue\nfalse\nmaximize x11configurerequest'
[[ $setup_rule == "$expected_setup_rule" ]] ||
  fail "Battle.net setup floats on-screen without a tiled WM frame" "$setup_rule"

pass "Battle.net setup floats on-screen without a tiled WM frame"

login_rule=$(OMARCHY_PATH="$ROOT" lua <<'LUA'
package.path = os.getenv("OMARCHY_PATH") .. "/?.lua;" .. package.path

o = {
  window = function(match, rules)
    if match.title == "^Battle\\.net Login$" then
      print(match.class)
      print(tostring(rules.float))
      print(tostring(rules.center))
      print(tostring(rules.size))
      print(rules.suppress_event)
    end
  end,
}

require("default.hypr.apps.battlenet")
LUA
)

expected_login_rule=$'^steam_app_battlenet$\ntrue\ntrue\nnil\nmaximize x11configurerequest'
[[ $login_rule == "$expected_login_rule" ]] ||
  fail "Battle.net login dialog floats without the launcher size" "$login_rule"

pass "Battle.net login dialog floats without the launcher size"

grep -Fq 'StartupWMClass=steam_app_battlenet' "$ROOT/default/applications/battlenet.desktop" ||
  fail "Battle.net desktop entry uses the Proton window class"
pass "Battle.net desktop entry uses the Proton window class"

child_rule=$(OMARCHY_PATH="$ROOT" lua <<'LUA'
package.path = os.getenv("OMARCHY_PATH") .. "/?.lua;" .. package.path

o = {
  window = function(match, rules)
    if match.title == "^$" then
      print(match.class)
      print(tostring(rules.float))
      print(tostring(rules.stay_focused))
      print(rules.min_size[1] .. "x" .. rules.min_size[2])
    end
  end,
}

require("default.hypr.apps.battlenet")
LUA
)

expected_child_rule=$'^steam_app_battlenet$\ntrue\ntrue\n1x1'
[[ $child_rule == "$expected_child_rule" ]] ||
  fail "Battle.net empty-title children stay floating with a min size" "$child_rule"

pass "Battle.net empty-title children stay floating with a min size"

grep -Fq 'tile = true' "$rules_file" ||
  fail "Battle.net main client must tile like other apps"
pass "Battle.net main client tiles like other apps"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

fake_home="$test_tmp/home"
mkdir -p "$fake_home/Games/battlenet/drive_c/Program Files (x86)/Battle.net"
touch "$fake_home/Games/battlenet/drive_c/Program Files (x86)/Battle.net/Battle.net Launcher.exe"

mock_bin="$test_tmp/bin"
mkdir -p "$mock_bin"

cat >"$mock_bin/umu-run" <<'SH'
#!/bin/bash
printf 'umu:%s\n' "$*" >>"$OMARCHY_TEST_LOG"
printenv WINEPREFIX PROTONPATH GAMEID PROTON_VERB >>"$OMARCHY_TEST_LOG"
SH

cat >"$mock_bin/hyprctl" <<'SH'
#!/bin/bash
printf 'hyprctl:%s\n' "$*" >>"$OMARCHY_TEST_HYPR_LOG"

case "$1" in
  clients)
    printf '%s\n' "${OMARCHY_TEST_CLIENTS_JSON:-[]}"
    ;;
  monitors)
    printf '%s\n' "${OMARCHY_TEST_MONITORS_JSON:-[]}"
    ;;
  activeworkspace)
    printf '{"id":5}\n'
    ;;
  dispatch|eval)
    exit 0
    ;;
  *)
    exit 1
    ;;
esac
SH

chmod +x "$mock_bin"/*

launch_log="$test_tmp/launch.log"
hypr_log="$test_tmp/hypr.log"

PATH="$mock_bin:$PATH" HOME="$fake_home" \
  OMARCHY_TEST_LOG="$launch_log" OMARCHY_TEST_HYPR_LOG="$hypr_log" \
  OMARCHY_TEST_CLIENTS_JSON='[]' \
  bash "$launch_script"

grep -Fq "umu:$fake_home/Games/battlenet/drive_c/Program Files (x86)/Battle.net/Battle.net Launcher.exe" "$launch_log" ||
  fail "Battle.net launcher starts umu-run when no window exists" "$(cat "$launch_log")"
grep -Fxq "$fake_home/Games/battlenet" "$launch_log" || fail "Battle.net launcher sets WINEPREFIX"
grep -Fxq "GE-Proton" "$launch_log" || fail "Battle.net launcher sets PROTONPATH"
grep -Fxq "umu-battlenet" "$launch_log" || fail "Battle.net launcher sets GAMEID"

pass "Battle.net launcher starts umu-run when no window exists"

>"$launch_log"
>"$hypr_log"

existing_clients='[{"address":"0xabc","class":"steam_app_battlenet","title":"Battle.net","monitor":1,"size":[1280,800],"floating":false}]'
existing_monitors='[{"id":1,"x":0,"y":0,"width":1920,"height":1080}]'

PATH="$mock_bin:$PATH" HOME="$fake_home" \
  OMARCHY_TEST_LOG="$launch_log" OMARCHY_TEST_HYPR_LOG="$hypr_log" \
  OMARCHY_TEST_CLIENTS_JSON="$existing_clients" \
  OMARCHY_TEST_MONITORS_JSON="$existing_monitors" \
  bash "$launch_script"

[[ -s $launch_log ]] && fail "Battle.net launcher must not start a second umu-run" "$(cat "$launch_log")"
grep -Fq 'hl.dsp.focus({ window = "address:0xabc" })' "$hypr_log" ||
  fail "Battle.net launcher focuses the existing window" "$(cat "$hypr_log")"
grep -Fq 'hl.dsp.window.move({ workspace = "5" })' "$hypr_log" ||
  fail "Battle.net launcher moves the existing window to the current workspace" "$(cat "$hypr_log")"
grep -Fq 'hl.dsp.window.move({ x = 320, y = 140 })' "$hypr_log" &&
  fail "Battle.net launcher must not center a tiled window" "$(cat "$hypr_log")"

pass "Battle.net launcher focuses an already-running tiled window instead of starting a second client"

>"$launch_log"
>"$hypr_log"

floating_clients='[{"address":"0xdef","class":"steam_app_battlenet","title":"Battle.net Login","monitor":1,"size":[362,719],"floating":true}]'

PATH="$mock_bin:$PATH" HOME="$fake_home" \
  OMARCHY_TEST_LOG="$launch_log" OMARCHY_TEST_HYPR_LOG="$hypr_log" \
  OMARCHY_TEST_CLIENTS_JSON="$floating_clients" \
  OMARCHY_TEST_MONITORS_JSON="$existing_monitors" \
  bash "$launch_script"

[[ -s $launch_log ]] && fail "Battle.net launcher must not start umu-run when a login window exists" "$(cat "$launch_log")"
grep -Fq 'hl.dsp.window.move({ x = 779, y = 180 })' "$hypr_log" ||
  fail "Battle.net launcher centers a floating login window" "$(cat "$hypr_log")"

pass "Battle.net launcher centers a floating login window on the focused monitor"
