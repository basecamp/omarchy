#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

if matches=$(rg -n 'root\.bar\.omarchyPath|/bin/omarchy-' "$ROOT/shell/plugins/panels" -g '*.qml'); then
  fail "panels do not resolve omarchy helpers through bar paths" "$matches"
fi

pass "panels avoid bar path resolution for omarchy helpers"
