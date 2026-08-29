#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

browser_lua="$ROOT/default/hypr/apps/browser.lua"

extract_pattern() {
  local tag=$1
  grep -F "tag = \"+$tag\"" "$browser_lua" | head -n1 |
    sed -n 's/^o\.window("\([^"]*\)".*$/\1/p'
}

chromium_pattern=$(extract_pattern chromium-based-browser)
[[ -n $chromium_pattern ]] || fail "browser.lua declares a chromium-based-browser rule" "pattern not found"

firefox_pattern=$(extract_pattern firefox-based-browser)
[[ -n $firefox_pattern ]] || fail "browser.lua declares a firefox-based-browser rule" "pattern not found"

matches() {
  [[ $1 =~ $2 ]]
}

for appid in google-chrome chromium brave-browser brave-origin helium Vivaldi-stable microsoft-edge; do
  matches "$appid" "$chromium_pattern" || fail "chromium rule tags $appid"
done
pass "chromium rule tags every chromium-based browser"

for appid in firefox librewolf; do
  matches "$appid" "$chromium_pattern" && fail "chromium rule keeps the firefox-based $appid untagged"
done
pass "chromium rule leaves firefox-based browsers untagged"

for appid in firefox zen librewolf; do
  matches "$appid" "$firefox_pattern" || fail "firefox rule tags $appid"
done
pass "firefox rule tags every firefox-based browser"

for appid in brave-browser chromium; do
  matches "$appid" "$firefox_pattern" && fail "firefox rule keeps the chromium-based $appid untagged"
done
pass "firefox rule leaves chromium-based browsers untagged"
