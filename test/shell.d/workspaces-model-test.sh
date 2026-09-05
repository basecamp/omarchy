#!/bin/bash

set -euo pipefail

# The workspace row is a Repeater, and a Repeater compares its model by
# identity: hand it a new array and every delegate is destroyed and rebuilt,
# however alike the two arrays are. The model used to be a function call
# allocating a fresh array on each evaluation, re-run whenever Hyprland created
# or destroyed a workspace -- so pressing SUPER+4 from an occupied workspace
# rebuilt the whole row, and leaving 4 empty rebuilt it again, while moving
# between workspaces that hold windows did not. That is the stutter that came
# and went. These pin the array staying put.

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

MODEL="$ROOT/shell/plugins/bar/widgets/WorkspacesModel.js"

node --check "$MODEL" || fail "WorkspacesModel.js parses"
pass "WorkspacesModel.js parses"

node -e '
const assert = require("assert")
const M = require(process.argv[1])
const ws = ids => ids.map(id => ({ id }))

// The row always offers 1-5.
assert.deepStrictEqual(M.workspaceIds(ws([])), [1, 2, 3, 4, 5])
assert.deepStrictEqual(M.workspaceIds(ws([1, 2, 3])), [1, 2, 3, 4, 5])
assert.deepStrictEqual(M.workspaceIds(ws([7, 1])), [1, 2, 3, 4, 5, 7])
assert.deepStrictEqual(M.workspaceIds(ws([10])), [1, 2, 3, 4, 5, 10])

// Out of range, and junk Hyprland should never send but might.
assert.deepStrictEqual(M.workspaceIds(ws([11, 0, -3])), [1, 2, 3, 4, 5])
assert.deepStrictEqual(M.workspaceIds([{}, null, { id: "2" }, { id: NaN }]), [1, 2, 3, 4, 5])
assert.deepStrictEqual(M.workspaceIds(null), [1, 2, 3, 4, 5])

// The one that matters. Creating or destroying a workspace inside 1-5 leaves
// the row identical, so the array -- and every delegate built from it -- is
// kept. This is the case that was rebuilding the row for no visible change.
const start = M.workspaceIds(ws([1, 2, 3]))
assert.strictEqual(M.stableIds(start, M.workspaceIds(ws([1, 2, 3, 4]))), start,
  "creating an empty workspace inside 1-5 keeps the array")
assert.strictEqual(M.stableIds(start, M.workspaceIds(ws([1]))), start,
  "destroying one inside 1-5 keeps the array")
assert.strictEqual(M.stableIds(start, M.workspaceIds(ws([1, 2, 3]))), start,
  "an unchanged list keeps the array")

// A workspace outside 1-5 really does change the row, and must not be kept.
const grown = M.stableIds(start, M.workspaceIds(ws([1, 2, 3, 7])))
assert.notStrictEqual(grown, start, "a workspace outside 1-5 replaces the array")
assert.deepStrictEqual(grown, [1, 2, 3, 4, 5, 7])
assert.strictEqual(M.stableIds(grown, M.workspaceIds(ws([1, 7]))), grown,
  "the grown row is itself kept while it still describes the same ids")
assert.notStrictEqual(M.stableIds(grown, M.workspaceIds(ws([1]))), grown,
  "losing that workspace shrinks the row back")

// Same length, different ids: length alone must not decide.
assert.notStrictEqual(M.stableIds([1, 2, 3, 4, 5, 7], [1, 2, 3, 4, 5, 8]), null)
assert.deepStrictEqual(M.stableIds([1, 2, 3, 4, 5, 7], [1, 2, 3, 4, 5, 8]), [1, 2, 3, 4, 5, 8])

// A first run has nothing to compare against.
assert.deepStrictEqual(M.stableIds(undefined, [1, 2, 3, 4, 5]), [1, 2, 3, 4, 5])

// The lookup a delegate reads, built once instead of scanned per delegate.
const map = M.byId(ws([1, 2, 3]))
assert.strictEqual(map[2].id, 2)
assert.strictEqual(map[9], undefined)
assert.deepStrictEqual(M.byId(null), {})
assert.deepStrictEqual(M.byId([null, {}, { id: "x" }]), {})
' "$MODEL" || fail "the workspace row keeps its array unless the ids really change"
pass "the workspace row keeps its array unless the ids really change"

# The widget must actually use it, or the model is just a well-tested orphan.
WIDGET="$ROOT/shell/plugins/bar/widgets/Workspaces.qml"
grep -q 'WorkspacesModel.stableIds' "$WIDGET" ||
  fail "the widget assigns its ids through stableIds"
! grep -qE 'model: root\.workspaceIds\(\)|columns:.*workspaceIds\(\)' "$WIDGET" ||
  fail "the widget no longer allocates a fresh model array in a binding"
pass "the widget takes its model through stableIds"

# The delegate reads the map built once per change rather than scanning the
# workspace list itself, which made drawing the row cost O(n^2) per rebuild.
grep -q 'root\.byId\[modelData\]' "$WIDGET" ||
  fail "the delegate reads the prebuilt workspace map"
! grep -q 'function workspaceById' "$WIDGET" ||
  fail "the per-delegate workspace scan is gone"
pass "the delegate reads a map built once per change"
