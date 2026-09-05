#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

tpl="$ROOT/default/themed/hyprland.lua.tpl"
[[ -f $tpl ]] || fail "hyprland theme template is present"

grep -F 'active_border = active_border_color' "$tpl" >/dev/null ||
  fail "template still themes general active_border"
grep -F 'decoration' "$tpl" >/dev/null || fail "template configures decoration"
grep -F 'glow' "$tpl" >/dev/null || fail "template configures decoration.glow"

# Glow colors must track the same themed border colors (#9737).
grep -E 'color\s*=\s*active_border_color' "$tpl" >/dev/null ||
  fail "glow.color uses the themed active border color"
grep -E 'color_inactive\s*=\s*inactive_border_color' "$tpl" >/dev/null ||
  fail "glow.color_inactive uses the themed inactive border color"
pass "hyprland theme template themes decoration.glow colors"

# glow block sits under decoration = { ... }
python3 - <<'PY' || fail "glow is nested under decoration in the template"
from pathlib import Path
import os
text = Path(os.environ["ROOT"], "default/themed/hyprland.lua.tpl").read_text()
# crude structure: decoration = { ... glow = { ... color = active_border_color
import re
m = re.search(r"decoration\s*=\s*\{([\s\S]*?)\n\s*\},", text)
assert m, "decoration block missing"
body = m.group(1)
assert re.search(r"glow\s*=\s*\{", body), "glow not inside decoration"
assert "color = active_border_color" in body
assert "color_inactive = inactive_border_color" in body
print("ok")
PY
pass "glow color keys nest under decoration.glow"
