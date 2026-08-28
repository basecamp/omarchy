#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

require_command jq

plugin="$ROOT/shell/plugins/panels/local-ai"

[[ -x $plugin/bin/omarchy-local-ai ]] || fail "plugin controller is executable"
[[ -x $ROOT/bin/omarchy-local-ai ]] || fail "omarchy local-ai command is executable"
[[ -f $plugin/manifest.json ]] || fail "plugin manifest exists"

id=$(jq -r .id "$plugin/manifest.json")
[[ $id == "omarchy.local-ai" ]] || fail "plugin uses the first-party namespace" "$id"

bash "$plugin/test/all"
