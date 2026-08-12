#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

run_node_test "workspace model sync" <<'JS'
const model = requireFromRoot('shell/plugins/bar/widgets/WorkspaceModel.js')

// The module keeps a cache between evaluations; ordering below matters.

let defaultIds = model.sync([])
assertDeepEqual(defaultIds, [1, 2, 3, 4, 5], 'an empty workspace set keeps the default workspaces')

const discovered = model.sync([{ id: 7 }, { id: 3 }, { id: 9 }])
assertDeepEqual(discovered, [1, 2, 3, 4, 5, 7, 9], 'discovered workspaces merge with the defaults, sorted')

const sameSet = model.sync([{ id: 3 }, { id: 9 }, { id: 7 }])
assert(discovered === sameSet, 'an unchanged id set returns the same array reference')

const grown = model.sync([{ id: 7 }, { id: 3 }, { id: 9 }, { id: 10 }])
assert(discovered !== grown, 'a changed id set replaces the array reference')
assertDeepEqual(grown, [1, 2, 3, 4, 5, 7, 9, 10], 'an added workspace appears in the new set')

const shrunk = model.sync([{ id: 7 }])
assertDeepEqual(shrunk, [1, 2, 3, 4, 5, 7], 'a removed workspace drops from the set')

const bounded = model.sync([{ id: 0 }, { id: -1 }, { id: 11 }, { id: 20 }, { id: 3 }])
assertDeepEqual(bounded, [1, 2, 3, 4, 5], 'out-of-range and duplicate ids are excluded')

const deduped = model.sync([{ id: 1 }, { id: 1 }, { id: 2 }, { id: 2 }, { id: 5 }, { id: 5 }])
assertDeepEqual(deduped, [1, 2, 3, 4, 5], 'duplicate discovered ids collapse into one entry')
JS