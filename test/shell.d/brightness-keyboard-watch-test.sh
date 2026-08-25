#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

require_command python3

python3 - "$ROOT/bin/omarchy-brightness-keyboard-watch" <<'PY'
import runpy
import sys

follow = runpy.run_path(sys.argv[1])["follow"]
g = follow.__globals__

class Seq:
    def __init__(self, values):
        self.values = list(values)
        self.applied = []

    def read_level(self):
        return self.values.pop(0) if self.values else self.applied[-1][0]

    def apply(self, cmd):
        self.applied.append((cmd.level, cmd.osd))

seq = Seq([1, 3, 3])
g["read_level"] = seq.read_level
g["apply"] = seq.apply
g["read_rgb"] = lambda: (1, 2, 3)

last = follow(0, osd=True)
if last != 3 or seq.applied != [(1, True), (3, True)]:
    raise SystemExit(f"catch-up last={last} applies={seq.applied}")

seq = Seq([2])
g["read_level"] = seq.read_level
g["apply"] = seq.apply
last = follow(2, osd=True)
if last != 2 or seq.applied != []:
    raise SystemExit(f"stable last={last} applies={seq.applied}")
PY

pass "follow applies every sysfs change that happens during a slow apply"
pass "follow is a no-op when the level did not change"
