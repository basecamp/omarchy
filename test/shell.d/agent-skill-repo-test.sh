#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

hits=$(rg -n 'basecamp/omarchy' "$ROOT/default/agents/skills" || true)
[[ -z $hits ]] || fail "shipped agent skills name omacom/omarchy, not the old basecamp owner" "$hits"
pass "shipped agent skills name omacom/omarchy"
