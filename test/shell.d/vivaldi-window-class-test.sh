#!/bin/bash

# Browser window tagging: browser.lua must give every Chromium-family browser —
# including Vivaldi — the +chromium-based-browser tag so they get the tile and
# opacity treatment instead of the generic -default-opacity.
#
# Regression guard for omacom/omarchy#9274: Hyprland reports Vivaldi's window
# class in lowercase ("vivaldi-stable"), but the rule used to spell it with a
# capital V, so Vivaldi never matched. The matcher must accept both cases.

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

browser_lua="$ROOT/default/hypr/apps/browser.lua"

rule=$(rg -m1 'chromium-based-browser' "$browser_lua" | rg 'o\.window' || true)
[[ -n $rule ]] || fail "browser.lua tags a chromium-based-browser window class"
pass "browser.lua tags a chromium-based-browser window class"

# Vivaldi's class is lowercase in Hyprland, so the matcher must cover both
# forms — the upper-case-only spelling misses it entirely.
rg -q '\[vV\]ivaldi-stable' "$browser_lua" \
  || fail "Vivaldi's class is matched in both cases" \
     "expected a [vV]ivaldi-stable alternative in browser.lua"
rg -q '[|]Vivaldi-stable\)' "$browser_lua" \
  && fail "Vivaldi's matcher is not case-sensitive on the initial letter" \
     "upper-case-only Vivaldi-stable would miss the lowercase window class"
pass "Vivaldi's class is matched in both cases"