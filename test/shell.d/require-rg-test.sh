#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

empty=$(mktemp -d)
trap 'rm -rf "$empty"' EXIT
# Keep dirname so the child can source base-test.sh; omit rg.
ln -s "$(command -v dirname)" "$empty/dirname"

output=$(PATH="$empty" /bin/bash "$ROOT/test/shell.d/panel-command-path-test.sh" 2>&1) &&
  fail "panel-command-path reports ok when rg is missing" "$output"
grep -q 'required command is available: rg' <<<"$output" ||
  fail "missing rg does not fail as a required command" "$output"
pass "missing rg fails the suite instead of skipping negative guards"
