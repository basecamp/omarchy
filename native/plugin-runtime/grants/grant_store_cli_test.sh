#!/bin/bash

set -euo pipefail

cli=$1
test_root=$(mktemp -d /tmp/omarchy-grant-cli-test.XXXXXX)
trap 'rm -rf "$test_root"' EXIT

fail() {
  echo "grant store CLI test: $1" >&2
  exit 1
}

expect_failure() {
  local expected=$1
  shift
  local output
  if output=$("$@" 2>&1); then
    fail "command unexpectedly succeeded"
  fi
  [[ $output == *"$expected"* ]] || fail "missing diagnostic: $expected"
}

empty='{"schemaVersion":1,"securePluginSchemaVersion":2,"legacySchemaV1Safe":false,"mutationSequence":0,"nextDecisionSequence":1,"plugins":[],"decisions":[]}'
expect_failure "schema-v2 plugin permissions are feature-gated" \
  "$cli" list --store "$test_root/gated"

actual=$(OMARCHY_PLUGIN_SCHEMA_V2_ENABLED=1 "$cli" list --store "$test_root/enabled")
[[ $actual == "$empty" ]] || fail "empty machine output changed"
[[ ! -e $test_root/enabled ]] || fail "list created the grant store"

expect_failure "schema v1 is unsafe host code" \
  "$cli" grant --schema-version 1
expect_failure "--yes never grants" \
  "$cli" grant --yes

binding=(
  --schema-version 2
  --plugin example.clock
  --revision aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
  --source-request bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
  --generation 1
  --required storage.private@1=quota:4096:1024
  --capability storage.private@1
)
preview=$(OMARCHY_PLUGIN_SCHEMA_V2_ENABLED=1 "$cli" diff \
  --store "$test_root/noninteractive" "${binding[@]}")
[[ $preview == *'"change":"added"'* ]] || fail "diff omitted update delta"
[[ ! -e $test_root/noninteractive ]] || fail "diff created the grant store"

expect_failure "require an interactive terminal" \
  env OMARCHY_PLUGIN_SCHEMA_V2_ENABLED=1 "$cli" grant \
  --store "$test_root/noninteractive" "${binding[@]}"
[[ ! -e $test_root/noninteractive ]] || \
  fail "non-interactive grant mutated the store"

echo "grant store CLI contract: ok"
