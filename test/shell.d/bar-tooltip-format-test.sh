#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

bar_qml="$ROOT/shell/plugins/bar/Bar.qml"
[[ -f $bar_qml ]] || fail "bar QML is present"

# Extract a short window after tooltipLabel for format assertions (#9940).
block=$(awk '
  /id: tooltipLabel/ { grab = 1 }
  grab { print; n++ }
  grab && n >= 12 { exit }
' "$bar_qml")

[[ -n $block ]] || fail "tooltipLabel block is present in Bar.qml"
[[ $block == *'textFormat:'* ]] || fail "tooltipLabel declares textFormat" "$block"

if [[ $block == *'textFormat: Text.PlainText'* ]]; then
  fail "tooltipLabel must not force PlainText (breaks rich HTML tooltips)" "$block"
fi

[[ $block == *'textFormat: Text.StyledText'* ]] ||
  fail "tooltipLabel uses StyledText for deliberate rich tooltips" "$block"
pass "bar tooltipLabel uses StyledText for rich tooltips"

# Must still satisfy the dynamic-text security scan (explicit textFormat).
require_command python3
if printf '%s\n' "$(python3 "$ROOT/test/shell.d/qml-text-format-scan.py" "$ROOT" 2>/dev/null || true)" |
  grep -F 'Bar.qml' | grep -F 'tooltip' >/dev/null; then
  fail "tooltipLabel must not appear as a textFormat scan violation"
fi
pass "tooltipLabel keeps an explicit textFormat for the security scan"
