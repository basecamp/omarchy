#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

sq="$ROOT/shell/shell.qml"
[[ -f $sq ]] || fail "shell.qml is present"

# finishPluginReload must not call the dead Qt.clearComponentCache (#9772).
if grep -F 'typeof Qt.clearComponentCache' "$sq" >/dev/null; then
  fail "shell.qml must not reference the non-existent Qt.clearComponentCache QML API"
fi

grep -F 'Qt.clearComponentCache has never been a QML API' "$sq" >/dev/null ||
  fail "shell.qml documents that the QML engine cache is not cleared on reload"
grep -F '#9772' "$sq" >/dev/null ||
  fail "shell.qml references the issue"
grep -F 'pluginRegistry.rescan()' "$sq" >/dev/null ||
  fail "shell.qml still calls rescan after reload"

# finishPluginReload still exists and guards correctly.
grep -F 'function finishPluginReload()' "$sq" >/dev/null ||
  fail "finishPluginReload function is still present"
grep -F '!shell.pluginReloading' "$sq" >/dev/null ||
  fail "finishPluginReload guards on pluginReloading"
pass "finishPluginReload removes dead clearComponentCache call"