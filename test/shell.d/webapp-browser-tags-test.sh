#!/bin/bash

# Chromium --app web apps must receive +chromium-based-browser under Hyprland's
# RE2 FullMatch class matching. Bare browser ids alone never full-match the
# <browser>-<host>__<path>-Default form from omarchy-launch-webapp.
#
# Regression guard for omacom/omarchy#9784. Uses Python re.fullmatch so the
# test matches Hyprland semantics (bash [[ =~ ]] is unanchored and would hide
# the bug).

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

browser_lua="$ROOT/default/hypr/apps/browser.lua"

chromium_pattern=$(
  grep -F 'tag = "+chromium-based-browser"' "$browser_lua" | head -n1 |
    sed -n 's/^o\.window("\([^"]*\)".*$/\1/p'
)
[[ -n $chromium_pattern ]] || fail "browser.lua declares a chromium-based-browser class rule"

# Decode Lua string escapes in the extracted pattern so Python sees the same
# bytes Hyprland's RE2 engine does after the Lua string is parsed.
chromium_pattern=$(
  PATTERN=$chromium_pattern python3 - <<'PY'
import codecs, os
print(codecs.decode(os.environ["PATTERN"], "unicode_escape"), end="")
PY
)

fullmatch() {
  local value=$1 pattern=$2
  PATTERN=$pattern VALUE=$value python3 - <<'PY'
import os, re, sys
sys.exit(0 if re.fullmatch(os.environ["PATTERN"], os.environ["VALUE"]) else 1)
PY
}

# Bare Chromium-family browser windows still match.
for appid in \
  chromium chrome Chrome google-chrome \
  brave-browser Brave-browser brave-origin \
  microsoft-edge Microsoft-edge Vivaldi-stable helium; do
  fullmatch "$appid" "$chromium_pattern" ||
    fail "chromium rule full-matches bare browser class $appid"
done
pass "chromium rule full-matches bare Chromium-family browser classes"

# Web apps launched via --app= use <browser>-<host>__<path>-Default.
for appid in \
  "chrome-example.com__-Default" \
  "chrome-example.com__path-Default" \
  "chromium-example.com__-Default" \
  "google-chrome-example.com__-Default" \
  "brave-outlook.office.com__mail_-Default" \
  "brave-origin-example.com__-Default" \
  "brave-browser-example.com__-Default" \
  "microsoft-edge-example.com__-Default" \
  "helium-example.com__-Default" \
  "Vivaldi-stable-example.com__-Default"; do
  fullmatch "$appid" "$chromium_pattern" ||
    fail "chromium rule full-matches webapp class $appid"
done
pass "chromium rule full-matches Chromium --app webapp classes"

# Non-Chromium classes and incomplete suffixes must stay untagged.
for appid in \
  firefox zen librewolf \
  "firefox-example.com__-Default" \
  chrome-evil \
  brave-something \
  not-a-browser; do
  fullmatch "$appid" "$chromium_pattern" &&
    fail "chromium rule leaves non-matching class $appid untagged"
done
pass "chromium rule leaves non-Chromium and incomplete classes untagged"

# The optional webapp suffix must be present so the YouTube/Zoom strip rules
# (browser-agnostic ^.+-youtube.com__.*) can see the tag they remove.
grep -Fq '(-.+-Default)?' "$browser_lua" ||
  fail "chromium rule allows the Chromium --app -...-Default webapp suffix"
pass "chromium rule includes the Chromium --app webapp class suffix"
