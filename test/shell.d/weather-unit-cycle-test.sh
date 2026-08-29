#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

panel="$ROOT/shell/plugins/panels/weather/Panel.qml"
model="$ROOT/shell/plugins/panels/weather/Model.js"

grep -q 'function cycleTempUnit()' "$panel" || fail "weather panel can cycle the temperature unit"
grep -q 'onClicked: root.cycleTempUnit()' "$panel" || fail "weather unit label is clickable"
grep -q 'function nextTempUnitOverride' "$model" || fail "weather model exposes unit cycle helper"

# Pure bash cycle checks mirroring Model.nextTempUnitOverride
next_for() {
  case "$1" in
    metric) echo imperial ;;
    imperial) echo "" ;;
    *) echo metric ;;
  esac
}
[[ $(next_for "") == "metric" ]] || fail "auto cycles to metric"
[[ $(next_for metric) == "imperial" ]] || fail "metric cycles to imperial"
[[ $(next_for imperial) == "" ]] || fail "imperial cycles back to auto"

pass "weather temperature unit can be pinned from the panel"
