#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

qml="$ROOT/shell/plugins/bar/indicators/Dictation.qml"
[[ -f $qml ]] || fail "Dictation indicator QML is present"

# active must include both non-idle voxtype states (#9675).
grep -E 'active:\s*state\s*===\s*"recording"\s*\|\|\s*state\s*===\s*"transcribing"' "$qml" >/dev/null ||
  fail "Dictation active covers recording and transcribing" "$(grep -n 'active:' "$qml")"

if grep -E 'active:\s*state\s*===\s*"recording"\s*$' "$qml" >/dev/null; then
  fail "Dictation must not treat only recording as active"
fi

grep -F 'state === "transcribing"' "$qml" >/dev/null ||
  fail "Dictation still maps the transcribing icon"
grep -F '󰔟' "$qml" >/dev/null || fail "Dictation keeps the transcribing spinner glyph"
pass "Dictation indicator stays active while recording or transcribing"
