#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

dropdown_qml=$(<"$ROOT/shell/Ui/Dropdown.qml")

if [[ $dropdown_qml != *'property string indicatorText: "󰅀"'* ]]; then
  fail "dropdown exposes its indicator text"
fi
pass "dropdown exposes its indicator text"

if [[ $dropdown_qml != *'property string indicatorFontFamily: fontFamily'* ]]; then
  fail "dropdown exposes its indicator font family"
fi
pass "dropdown exposes its indicator font family"

if [[ $dropdown_qml != *'text: root.indicatorText'* ]] || [[ $dropdown_qml != *'font.family: root.indicatorFontFamily'* ]]; then
  fail "dropdown renders the indicator with its dedicated properties"
fi
pass "dropdown renders the indicator with its dedicated properties"
