#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

bar_qml="$ROOT/shell/plugins/bar/Bar.qml"
[[ -f $bar_qml ]] || fail "bar QML is present"

# moduleDropAtScene must create empty-region candidates (#9842).
grep -F 'addEmptyRegionCandidate' "$bar_qml" >/dev/null ||
  fail "moduleDropAtScene adds empty region candidates"

grep -F 'seenRegions' "$bar_qml" >/dev/null ||
  fail "moduleDropAtScene tracks which regions have visible slots"

# Synthetic candidates carry a region string.
python3 - <<'PY' || fail "empty-region candidate structure is correct"
from pathlib import Path
import os, re

bar = Path(os.environ["ROOT"], "shell/plugins/bar/Bar.qml").read_text()

# Find addEmptyRegionCandidate calls and verify they pass region strings.
calls = re.findall(r'addEmptyRegionCandidate\("([^"]+)"', bar)
assert "left" in calls, "left empty region has a drop candidate"
assert "center" in calls, "center empty region has a drop candidate"
assert "right" in calls, "right empty region has a drop candidate"

# Synthetic slot must have region + moduleName.
assert 'region: region' in bar
assert 'moduleName: ""' in bar

# nearestDropTarget must be called after empty-region augmentation.
func_start = bar.index("function moduleDropAtScene")
func_end = bar.index("\n  function visibleModuleSlot", func_start)
body = bar[func_start:func_end]
candidates_pos = body.index("return BarModel.nearestDropTarget")
assert "addEmptyRegionCandidate" in body[:candidates_pos], \
  "empty-region candidates are added before nearestDropTarget"
print("ok")
PY
pass "empty-region candidates are added to moduleDropAtScene"