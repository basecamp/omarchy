#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

require_command node

# End-to-end coverage of the query-plugin path with the real bins and the real
# MenuModel.js (query -> plugin selection -> bin --print -> row -> action).
if node "$ROOT/test/shell.d/menu-query-plugins-integration.js"; then
  pass "query-plugin integration with real bins"
else
  fail "query-plugin integration with real bins"
fi
