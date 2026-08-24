#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

grep -Fq 'sourceSize.width: 32 * Screen.devicePixelRatio' "$ROOT/shell/plugins/ultimate-taskbar/TaskButton.qml" \
  || fail "Superbar icons request a device-pixel sourceSize so they are not washed out"
grep -Fq 'sourceSize.height: 32 * Screen.devicePixelRatio' "$ROOT/shell/plugins/ultimate-taskbar/TaskButton.qml" \
  || fail "Superbar icons request a device-pixel sourceSize height"
pass "Superbar icons use a device-pixel sourceSize"
