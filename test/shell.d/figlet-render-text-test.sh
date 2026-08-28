#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/base-test.sh"

tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT

cat >"$tmp_dir/pyfiglet.py" <<'PY'
class FontInfo:
  height = 2


class Figlet:
  def __init__(self, font, width, justify):
    self.Font = FontInfo()

  def renderText(self, text):
    return {
      "SHORT": "SS\nSS\n",
      "LONG": "LLLLLL\nLLLLLL\n",
    }.get(text, "")
PY

result=$(PYTHONPATH="$tmp_dir:$ROOT/default/figlet" python - <<'PY'
from render_text import render_centered

print(render_centered("SHORT\nLONG", "test"), end="")
PY
)

[[ $result == $'  SS\n  SS\nLLLLLL\nLLLLLL' ]] \
  || fail "multiline FIGlet output centers shorter blocks" "$result"
pass "multiline FIGlet output centers shorter blocks"

result=$(PYTHONPATH="$tmp_dir:$ROOT/default/figlet" python - <<'PY'
from render_text import render_centered

print(render_centered("LONG\n\nSHORT", "test"), end="")
PY
)

[[ $result == $'LLLLLL\nLLLLLL\n\n\n  SS\n  SS' ]] \
  || fail "multiline FIGlet output preserves empty lines" "$result"
pass "multiline FIGlet output preserves empty lines"

preview_renderer="$ROOT/default/figlet/render-previews.py"
if rg -q 'text-anchor="middle"' "$preview_renderer"; then
  fail "FIGlet preview rows retain their font-defined horizontal offsets"
fi
rg -q 'f.*<text x="\{padding\}"' "$preview_renderer" \
  || fail "FIGlet preview rows share one left edge"
pass "FIGlet preview rows retain their font-defined horizontal offsets"
