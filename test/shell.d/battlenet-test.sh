#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

install_script="$ROOT/bin/omarchy-install-gaming-battlenet"

[[ ! -f $ROOT/applications/battlenet.desktop ]] || fail "Battle.net launcher is not part of default application refresh"
[[ -f $ROOT/default/applications/battlenet.desktop ]] || fail "Battle.net launcher template is available to the installer"
grep -F '$OMARCHY_PATH/default/applications/battlenet.desktop' "$install_script" >/dev/null ||
  fail "Battle.net installer installs the launcher from the installer-only template"

pass "Battle.net launcher is only installed by the Battle.net installer"
