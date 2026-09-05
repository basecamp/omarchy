#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT

export OMARCHY_PATH="$tmp_dir/missing-omarchy"
export OMARCHY_MIGRATION_STATE="$tmp_dir/state"
mkdir -p "$OMARCHY_MIGRATION_STATE"

set +e
out=$("$ROOT/bin/omarchy-migrate" --pending 2>&1)
status=$?
set -e

(( status == 2 )) || fail "migrate --pending exits 2 when migrations dir is missing" "status=$status out=$out"
[[ $out == *migrations\ directory\ missing* ]] || fail "migrate --pending mentions the missing directory" "$out"
pass "migrate --pending fails closed when OMARCHY_PATH has no migrations"
