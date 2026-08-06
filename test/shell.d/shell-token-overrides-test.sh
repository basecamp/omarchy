#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

style="$ROOT/shell/Commons/Style.qml"

# Every token a section reads has to be writable by applyShellValues, or the
# property is unreachable from any shell.toml, theme or user. [font] and
# [spacing] pass unknown keys straight through; [bar] used to whitelist two of
# its six, leaving icon-slot, icon-canvas, icon-font and status-slot dead.
bar_branch=$(awk '/section === "bar"/,/section === "spacing"/' "$style")
[[ -n $bar_branch ]] || fail "the [bar] branch of applyShellValues is readable"

while read -r token; do
  [[ -n $token ]] || continue
  case $token in
    scale-with-font) continue ;;
  esac
  if grep -qF "\"$token\"" <<<"$bar_branch"; then
    fail "[bar] accepts $token without naming it, so new tokens do not need parser changes"
  fi
done < <(grep -oE 'barToken\("[a-z-]+"' "$style" | sed 's/barToken("//;s/"//')
pass "every [bar] token Style reads can be set from shell.toml"
