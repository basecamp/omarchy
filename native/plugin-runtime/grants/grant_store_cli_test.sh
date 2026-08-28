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
  env -u OMARCHY_PLUGIN_SCHEMA_V2_ENABLED "$cli" list --store "$test_root/gated"

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

human=$(OMARCHY_PLUGIN_SCHEMA_V2_ENABLED=1 "$cli" diff \
  --format human --store "$test_root/noninteractive" "${binding[@]}")
[[ $human == *"Plugin ID: example.clock"* ]] || fail "human diff omitted canonical plugin identity"
[[ $human == *"Revision: aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"* ]] || \
  fail "human diff abbreviated spoof-resistant revision identity"
[[ $human == *"[NEW] Private plugin storage"* && $human == *"Choice: required"* ]] || \
  fail "human diff omitted capability wording or requirement"

expect_failure "require an interactive terminal" \
  env OMARCHY_PLUGIN_SCHEMA_V2_ENABLED=1 "$cli" grant \
  --store "$test_root/noninteractive" "${binding[@]}"
[[ ! -e $test_root/noninteractive ]] || \
  fail "non-interactive grant mutated the store"

expect_failure "review requires an interactive terminal" \
  env OMARCHY_PLUGIN_SCHEMA_V2_ENABLED=1 "$cli" review \
  --store "$test_root/noninteractive-review" \
  "${binding[@]:0:${#binding[@]}-2}"
[[ ! -e $test_root/noninteractive-review ]] || \
  fail "non-interactive review mutated the store"

review_binding=(
  --schema-version 2
  --plugin example.clock
  --revision aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
  --source-request bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
  --generation 2
  --optional audio.play-cue@1=tokens:complete
  --required storage.private@1=quota:4096:1024
)
printf -v review_command '%q ' env OMARCHY_PLUGIN_SCHEMA_V2_ENABLED=1 \
  "$cli" review --store "$test_root/interactive-review" "${review_binding[@]}"
printf -v cancelled_review_command '%q ' env OMARCHY_PLUGIN_SCHEMA_V2_ENABLED=1 \
  "$cli" review --store "$test_root/cancelled-review" "${review_binding[@]}"
set +e
cancelled_output=$(printf 'deny\n' | script -qec "$cancelled_review_command" /dev/null 2>&1)
cancelled_status=$?
set -e
(( cancelled_status != 0 )) || fail "incomplete review unexpectedly succeeded"
[[ $cancelled_output == *"permission review cancelled"* ]] || \
  fail "incomplete review omitted its cancellation diagnostic"
[[ ! -e $test_root/cancelled-review ]] || \
  fail "cancelled whole-policy review persisted a partial decision"

review_output=$(printf 'deny\ngrant\n' | script -qec "$review_command" /dev/null)
[[ $review_output == *"Type grant or deny for audio.play-cue@1 (optional)"* ]] || \
  fail "review did not identify the optional choice"
[[ $review_output == *"Type grant or deny for storage.private@1 (required)"* ]] || \
  fail "review did not identify the required choice"
review_state=$(OMARCHY_PLUGIN_SCHEMA_V2_ENABLED=1 "$cli" list \
  --store "$test_root/interactive-review")
[[ $review_state == *'"id":"audio.play-cue","version":1},"scope":{"kind":"tokens","values":["complete"]},"state":"denied"'* ]] || \
  fail "explicit optional denial was not persisted"
[[ $review_state == *'"id":"storage.private","version":1},"scope":{"kind":"quota","totalBytes":4096,"itemBytes":1024},"state":"granted"'* ]] || \
  fail "explicit required grant was not persisted"

echo "grant store CLI contract: ok"
