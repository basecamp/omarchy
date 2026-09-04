#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

require_command python3

ROOT="$ROOT" python3 <<'PY' || fail "Meet PiP title regex matches ASCII hyphen, en dash, and em dash"
import os
import pathlib
import re
import sys

text = pathlib.Path(os.environ["ROOT"], "default/hypr/apps/pip.lua").read_text()
match = re.search(r'title = "(\^Meet[^"]+)"', text)
if match is None:
    print("pip.lua has no Meet title rule", file=sys.stderr)
    sys.exit(1)

pattern = match.group(1)
cases = {
    "Meet - Team standup": True,
    "Meet – Team standup": True,
    "Meet — Team standup": True,
    "Meet": False,
    "Meeting notes": False,
    "Chrome - Meet": False,
}

for title, should_match in cases.items():
    matched = re.search(pattern, title) is not None
    if matched != should_match:
        print(f"{title!r} vs {pattern!r}: matched={matched} expected={should_match}", file=sys.stderr)
        sys.exit(1)
PY
pass "Meet PiP title regex matches ASCII hyphen, en dash, and em dash"
